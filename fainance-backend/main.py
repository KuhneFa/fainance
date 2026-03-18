import logging
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware

from categorizer import categorize_transactions, check_ollama_health
from database import (
    get_analysis,
    get_cached_insights,
    get_transactions,
    init_db,
    save_insights,
    save_transactions,
    save_upload_session,
    update_transaction_category,
)
from insights import generate_insights
from models import AnalysisResult, InsightRequest, InsightResponse, Transaction

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("🚀 Starte Finance AI Backend...")
    init_db()
    logger.info("✅ Datenbank initialisiert")
    health = await check_ollama_health()
    if health["status"] == "ok":
        logger.info(f"✅ Ollama verbunden. Modell: {health['model']}")
    else:
        logger.warning(f"⚠️  Ollama: {health.get('message', health['status'])}")
    yield
    logger.info("👋 Backend wird heruntergefahren...")


app = FastAPI(
    title="Finance AI API",
    description="Lokale Finanzanalyse mit Ollama LLM",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://10.0.2.2:8000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", tags=["Health"])
async def root():
    ollama_health = await check_ollama_health()
    return {
        "status": "running",
        "ollama": ollama_health,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/upload-csv", tags=["Upload"], status_code=status.HTTP_201_CREATED)
async def upload_csv(
    file: UploadFile = File(...),
    bank_name: str = Form(default="auto"),
    user_context: str = Form(default=""),
):
    """
    Nimmt eine CSV-Datei entgegen, kategorisiert alle Transaktionen
    und generiert automatisch LLM-Insights.

    - **file**: CSV-Datei vom Bankkonto
    - **bank_name**: Bankname oder 'auto' für automatische Erkennung
    - **user_context**: Optionaler Kontext z.B. 'Ich bin Student'
    """
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

    file_bytes = await file.read()
    if len(file_bytes) > 10 * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Datei zu groß. Maximum: 10 MB.",
        )

    logger.info(f"CSV-Upload: '{file.filename}' ({len(file_bytes)} Bytes)")

    # ── CSV parsen ─────────────────────────────────────────────────────────────
    try:
        from parser import BANK_FORMATS, parse_csv

        selected_format = None
        if bank_name != "auto":
            selected_format = next(
                (f for f in BANK_FORMATS if f.name.lower() == bank_name.lower()),
                None,
            )
            if selected_format is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Unbekannte Bank: '{bank_name}'.",
                )
        transactions = parse_csv(file_bytes, selected_format)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"CSV konnte nicht verarbeitet werden: {e}",
        )

    # ── Kategorisieren ─────────────────────────────────────────────────────────
    try:
        categorized = await categorize_transactions(transactions)
    except ConnectionError:
        categorized = [
            t.model_copy(update={"category": "Sonstiges"}) for t in transactions
        ]

    # ── Speichern ──────────────────────────────────────────────────────────────
    upload_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    save_upload_session(
        session_id=upload_id,
        filename=file.filename,
        uploaded_at=timestamp,
        row_count=len(categorized),
    )
    save_transactions(categorized, upload_id)
    logger.info(f"Upload {upload_id}: {len(categorized)} Transaktionen gespeichert.")

    # ── Insights automatisch generieren und cachen ─────────────────────────────
    # Läuft nach dem Speichern — Fehler hier brechen den Upload nicht ab.
    try:
        analysis = get_analysis(upload_id)
        insights = await generate_insights(
            analysis,
            user_context=user_context if user_context else None,
        )
        save_insights(upload_id, insights)
        logger.info(f"Insights für {upload_id} generiert und gecacht.")
    except Exception as e:
        logger.warning(f"Insights-Generierung fehlgeschlagen (non-fatal): {e}")

    return {
        "upload_id": upload_id,
        "filename": file.filename,
        "transaction_count": len(categorized),
        "uploaded_at": timestamp,
        "message": f"{len(categorized)} Transaktionen verarbeitet.",
    }


@app.get("/analysis/{upload_id}", response_model=AnalysisResult, tags=["Analysis"])
async def get_analysis_endpoint(upload_id: str):
    """Aggregierte Ausgaben-Analyse für das Dashboard."""
    try:
        uuid.UUID(upload_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ungültige upload_id.",
        )
    try:
        return get_analysis(upload_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Keine Daten für upload_id '{upload_id}'.",
        )


@app.get(
    "/transactions/{upload_id}",
    response_model=list[Transaction],
    tags=["Analysis"],
)
async def get_transactions_endpoint(
    upload_id: str, limit: int = 100, offset: int = 0
):
    """Rohtransaktionen eines Uploads (paginiert)."""
    try:
        uuid.UUID(upload_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ungültige upload_id.",
        )
    if limit > 500:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="limit darf maximal 500 sein.",
        )
    transactions = get_transactions(upload_id)
    return transactions[offset: offset + limit]


@app.get(
    "/insights/{upload_id}",
    response_model=InsightResponse,
    tags=["Insights"],
)
async def get_insights_endpoint(upload_id: str, regenerate: bool = False):
    """
    Gibt Insights für einen Upload zurück.
    Nutzt den Cache — kein LLM-Aufruf wenn Insights bereits vorhanden.

    - **regenerate**: Auf true setzen um Insights neu zu generieren
    """
    try:
        uuid.UUID(upload_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ungültige upload_id.",
        )

    # Cache prüfen
    if not regenerate:
        cached = get_cached_insights(upload_id)
        if cached:
            logger.info(f"Insights aus Cache für {upload_id}")
            return cached

    # Neu generieren
    try:
        analysis = get_analysis(upload_id)
        insights = await generate_insights(analysis)
        save_insights(upload_id, insights)
        return insights
    except Exception as e:
        logger.error(f"Insights fehlgeschlagen: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Insights konnten nicht generiert werden.",
        )


@app.post("/insights", response_model=InsightResponse, tags=["Insights"])
async def post_insights(request: InsightRequest):
    """
    Generiert Insights für übergebene Analysedaten.
    Für Fälle wo keine upload_id vorhanden ist.
    """
    try:
        return await generate_insights(
            request.analysis,
            user_context=request.user_context,
        )
    except Exception as e:
        logger.error(f"Insights fehlgeschlagen: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Insights konnten nicht generiert werden.",
        )


@app.patch("/transactions/{transaction_id}/category", tags=["Analysis"])
async def update_category(transaction_id: int, category: str):
    """Manuelle Kategorie-Korrektur durch den Nutzer."""
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