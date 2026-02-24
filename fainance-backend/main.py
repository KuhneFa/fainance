import logging
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware

from categorizer import categorize_transactions, check_ollama_health, generate_insights
from database import (
    get_analysis,
    get_transactions,
    init_db,
    save_transactions,
    save_upload_session,
    update_transaction_category,
)
from models import InsightRequest, InsightResponse, AnalysisResult, Transaction

# ── Logging konfigurieren ──────────────────────────────────────────────────────
# Logging ist in Produktion unverzichtbar. Wir schreiben in die Konsole,
# später kannst du das auf eine Datei oder einen Log-Service umleiten.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


# ── Lifespan: Startup & Shutdown ───────────────────────────────────────────────
# Der @asynccontextmanager teilt den Code in zwei Hälften:
# Alles VOR `yield` läuft beim Start, alles NACH `yield` beim Herunterfahren.
@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── STARTUP ────────────────────────────────────────────────────────────────
    logger.info("🚀 Starte Finance AI Backend...")

    # Datenbank initialisieren (erstellt Tabellen falls nicht vorhanden)
    init_db()
    logger.info("✅ Datenbank initialisiert")

    # Ollama-Verbindung prüfen
    health = await check_ollama_health()
    if health["status"] == "ok":
        logger.info(f"✅ Ollama verbunden. Modell: {health['model']}")
    else:
        # Wir crashen nicht — die App kann starten, gibt aber Warnungen aus.
        # Kategorisierung schlägt dann zur Laufzeit fehl mit einer klaren Fehlermeldung.
        logger.warning(f"⚠️  Ollama-Problem: {health.get('message', health['status'])}")

    yield  # ← App läuft hier

    # ── SHUTDOWN ───────────────────────────────────────────────────────────────
    logger.info("👋 Backend wird heruntergefahren...")


# ── FastAPI-App erstellen ──────────────────────────────────────────────────────
app = FastAPI(
    title="Finance AI API",
    description="Lokale Finanzanalyse mit Ollama LLM",
    version="0.1.0",
    lifespan=lifespan,
)


# ── CORS-Middleware ────────────────────────────────────────────────────────────
# Wir erlauben explizit nur lokale Origins. In Produktion würdest du hier
# deine echte Domain eintragen: ["https://deine-app.com"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",   # React Dev Server (falls du später Web baust)
        "http://localhost:8080",   # Flutter Web Dev Server
        "http://127.0.0.1:8080",
        "http://10.0.2.2:8000",    # Android Emulator → Host-Maschine
        # iOS Simulator nutzt direkt localhost, kein spezieller Host nötig
    ],
    allow_credentials=True,
    allow_methods=["*"],           # GET, POST, PUT, DELETE, OPTIONS
    allow_headers=["*"],
)


# ── Hilfsfunktionen ────────────────────────────────────────────────────────────
def generate_upload_id() -> str:
    """Generiert eine eindeutige ID für jeden CSV-Upload."""
    return str(uuid.uuid4())


def get_current_timestamp() -> str:
    """ISO 8601 Timestamp in UTC — immer UTC speichern, niemals lokale Zeit."""
    return datetime.now(timezone.utc).isoformat()


# ── Endpoints ─────────────────────────────────────────────────────────────────

# ── GET / ─────────────────────────────────────────────────────────────────────
@app.get("/", tags=["Health"])
async def root():
    """Health-Check Endpoint. Gibt den Status aller Abhängigkeiten zurück."""
    ollama_health = await check_ollama_health()
    return {
        "status": "running",
        "ollama": ollama_health,
        "timestamp": get_current_timestamp(),
    }


# ── POST /upload-csv ──────────────────────────────────────────────────────────
@app.post("/upload-csv", tags=["Upload"], status_code=status.HTTP_201_CREATED)
async def upload_csv(
    file: UploadFile = File(...),
    bank_name: str = Form(default="auto"),  # "auto", "Sparkasse", "N26", etc.
):
    """
    Nimmt eine CSV-Datei entgegen, parst sie, kategorisiert alle Transaktionen
    mit Ollama und speichert alles in der Datenbank.

    - **file**: Die CSV-Datei vom Bankkonto
    - **bank_name**: Optional. Bankname zur Format-Erkennung. Default: automatisch.

    Returns: upload_id die für alle weiteren Endpoints benötigt wird.
    """

    # ── Eingabe validieren ─────────────────────────────────────────────────────
    if not file.filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kein Dateiname angegeben.",
        )

    if not file.filename.lower().endswith(".csv"):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Nur CSV-Dateien werden unterstützt.",
        )

    # Dateigröße prüfen: max 10 MB
    # Wir lesen zuerst in Bytes, dann prüfen wir die Größe
    file_bytes = await file.read()
    max_size = 10 * 1024 * 1024  # 10 MB in Bytes
    if len(file_bytes) > max_size:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Datei zu groß. Maximum: 10 MB.",
        )

    logger.info(f"CSV-Upload: '{file.filename}' ({len(file_bytes)} Bytes)")

    # ── CSV parsen ─────────────────────────────────────────────────────────────
    try:
        from parser import BANK_FORMATS, parse_csv

        # Bank-Format aus dem Form-Parameter auflösen
        selected_format = None
        if bank_name != "auto":
            selected_format = next(
                (f for f in BANK_FORMATS if f.name.lower() == bank_name.lower()),
                None,
            )
            if selected_format is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Unbekannte Bank: '{bank_name}'. "
                           f"Verfügbar: {[f.name for f in BANK_FORMATS]}",
                )

        transactions = parse_csv(file_bytes, selected_format)

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"CSV konnte nicht verarbeitet werden: {str(e)}",
        )

    # ── Kategorisieren ─────────────────────────────────────────────────────────
    try:
        categorized = await categorize_transactions(transactions)
    except ConnectionError as e:
        # Ollama nicht erreichbar: Transaktionen trotzdem speichern,
        # aber ohne Kategorien (alle "Sonstiges").
        logger.error(f"Ollama nicht erreichbar: {e}")
        categorized = [
            t.model_copy(update={"category": "Sonstiges"}) for t in transactions
        ]

    # ── In Datenbank speichern ─────────────────────────────────────────────────
    upload_id = generate_upload_id()
    timestamp = get_current_timestamp()

    save_upload_session(
        session_id=upload_id,
        filename=file.filename,
        uploaded_at=timestamp,
        row_count=len(categorized),
    )
    save_transactions(categorized, upload_id)

    logger.info(
        f"Upload {upload_id}: {len(categorized)} Transaktionen gespeichert."
    )

    return {
        "upload_id": upload_id,
        "filename": file.filename,
        "transaction_count": len(categorized),
        "uploaded_at": timestamp,
        "message": f"{len(categorized)} Transaktionen erfolgreich verarbeitet.",
    }


# ── GET /analysis/{upload_id} ─────────────────────────────────────────────────
@app.get(
    "/analysis/{upload_id}",
    response_model=AnalysisResult,
    tags=["Analysis"],
)
async def get_analysis_endpoint(upload_id: str):
    """
    Gibt die aggregierte Ausgaben-Analyse für einen Upload zurück.
    Das ist das Objekt das im Flutter-Dashboard als Charts dargestellt wird.
    """
    # UUID-Format validieren um SQL-Injection-Versuche früh abzufangen
    try:
        uuid.UUID(upload_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ungültige upload_id. Muss eine UUID sein.",
        )

    try:
        analysis = get_analysis(upload_id)
    except Exception as e:
        logger.error(f"Fehler bei Analyse für {upload_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Keine Daten für upload_id '{upload_id}' gefunden.",
        )

    return analysis


# ── GET /transactions/{upload_id} ─────────────────────────────────────────────
@app.get(
    "/transactions/{upload_id}",
    response_model=list[Transaction],
    tags=["Analysis"],
)
async def get_transactions_endpoint(upload_id: str, limit: int = 100, offset: int = 0):
    """
    Gibt die Rohtransaktionen eines Uploads zurück (paginiert).
    Nützlich für die Detailansicht in der App.

    - **limit**: Max. Anzahl Transaktionen (default: 100)
    - **offset**: Für Pagination, z.B. offset=100 für die zweite Seite
    """
    try:
        uuid.UUID(upload_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ungültige upload_id.",
        )

    # Limit nach oben begrenzen damit niemand 100.000 Zeilen auf einmal abfragt
    if limit > 500:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="limit darf maximal 500 sein.",
        )

    transactions = get_transactions(upload_id)
    return transactions[offset : offset + limit]


# ── POST /insights ────────────────────────────────────────────────────────────
@app.post(
    "/insights",
    response_model=InsightResponse,
    tags=["Insights"],
)
async def get_insights(request: InsightRequest):
    """
    Schickt die aggregierten Finanzdaten an Ollama und gibt strukturierte
    Spartipps und Warnungen zurück.

    SICHERHEIT: Dieser Endpoint empfängt niemals Rohtransaktionen —
    nur die aggregierten Summaries aus /analysis.
    """
    try:
        insights = await generate_insights(request)
        return insights
    except ConnectionError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"LLM nicht erreichbar: {str(e)}",
        )
    except Exception as e:
        logger.error(f"Fehler bei Insights-Generierung: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Interner Fehler bei der Analyse.",
        )


# ── PATCH /transactions/{transaction_id}/category ────────────────────────────
@app.patch(
    "/transactions/{transaction_id}/category",
    tags=["Analysis"],
)
async def update_category(transaction_id: int, category: str):
    """
    Erlaubt dem Nutzer, eine Kategorie manuell zu korrigieren.
    Das LLM macht manchmal Fehler — dieser Endpoint gibt Kontrolle zurück.
    """
    from models import VALID_CATEGORIES

    if category not in VALID_CATEGORIES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Ungültige Kategorie. Erlaubt: {sorted(VALID_CATEGORIES)}",
        )

    try:
        update_transaction_category(transaction_id, category)
    except Exception as e:
        logger.error(f"Kategorie-Update fehlgeschlagen: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Kategorie konnte nicht aktualisiert werden.",
        )

    return {"transaction_id": transaction_id, "category": category, "status": "updated"}