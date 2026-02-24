import json
import logging
import re
from typing import Any

import aiohttp

from models import Transaction, InsightRequest, InsightResponse, VALID_CATEGORIES

logger = logging.getLogger(__name__)

# ── Konfiguration ──────────────────────────────────────────────────────────────
OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "mistral:7b-instruct-q4_0"

# Wie viele Transaktionen pro LLM-Aufruf. Zu groß = unzuverlässig. Zu klein = langsam.
BATCH_SIZE = 20

# Maximale Zeit die wir auf Ollama warten (in Sekunden).
# Auf einem MacBook mit 16GB kann ein Batch schon mal 30s dauern.
OLLAMA_TIMEOUT = 120


# ── System-Prompt ──────────────────────────────────────────────────────────────
# Der System-Prompt definiert die "Persönlichkeit" und Aufgabe des Modells.
# Er wird bei jedem Call mitgeschickt aber nie vom Nutzer gesehen.
# Wichtig: So präzise wie möglich, mit Beispielen und klaren Constraints.
CATEGORIZE_SYSTEM_PROMPT = f"""Du bist ein präziser Finanz-Kategorisierer.
Deine einzige Aufgabe ist es, Banktransaktionen einer Kategorie zuzuordnen.

ERLAUBTE KATEGORIEN (nur diese, keine anderen):
{json.dumps(sorted(VALID_CATEGORIES), ensure_ascii=False, indent=2)}

REGELN:
1. Antworte NUR mit einem JSON-Array. Kein Text davor oder danach.
2. Jedes Element hat genau zwei Felder: "id" (integer) und "category" (string).
3. Verwende AUSSCHLIESSLICH Kategorien aus der obigen Liste.
4. Bei Unsicherheit wähle "Sonstiges".
5. Einnahmen (positive Beträge) kategorisiere als "Sonstiges".

BEISPIELE:
Input:
[
  {{"id": 1, "description": "REWE SAGT DANKE", "amount": -34.50}},
  {{"id": 2, "description": "Miete Januar Überw.", "amount": -850.00}},
  {{"id": 3, "description": "Gehalt Februar", "amount": 2800.00}},
  {{"id": 4, "description": "Fitnessstudio Monatsbeitrag", "amount": -29.90}},
  {{"id": 5, "description": "Amazon Prime", "amount": -8.99}}
]

Output:
[
  {{"id": 1, "category": "Lebensmittel"}},
  {{"id": 2, "category": "Miete"}},
  {{"id": 3, "category": "Sonstiges"}},
  {{"id": 4, "category": "Sport"}},
  {{"id": 5, "category": "Unterhaltung"}}
]"""


INSIGHTS_SYSTEM_PROMPT = """Du bist ein freundlicher, aber ehrlicher persönlicher Finanzberater.
Du analysierst Ausgaben und gibst konstruktive, konkrete Tipps auf Deutsch.
Antworte NUR mit einem JSON-Objekt. Kein Text davor oder danach.
Das JSON-Objekt hat genau diese vier Felder:
- "summary": string (2-3 Sätze Gesamteinschätzung)
- "warnings": array of strings (Kategorien wo zu viel ausgegeben wird, max 3)
- "tips": array of strings (konkrete Spartipps, max 5)
- "positive": array of strings (was gut läuft, max 3)"""


# ── Ollama HTTP-Client ─────────────────────────────────────────────────────────
async def _call_ollama(system_prompt: str, user_message: str) -> str:
    """
    Sendet einen Request an die lokale Ollama-API und gibt den Antwort-Text zurück.

    Wir verwenden aiohttp statt requests, weil FastAPI auf asyncio basiert.
    `async/await` bedeutet: während Ollama rechnet, kann FastAPI andere
    Requests bedienen — der Server blockiert nicht.

    Args:
        system_prompt: Instruktionen für das Modell (unsichtbar für den "Nutzer").
        user_message: Der eigentliche Input (die Transaktionen als JSON-String).

    Returns:
        Den Antwort-Text des Modells (sollte valides JSON sein).
    """
    payload: dict[str, Any] = {
        "model": OLLAMA_MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
        "stream": False,   # Wir wollen die vollständige Antwort, nicht Token für Token
        "options": {
            "temperature": 0.1,   # Niedrig = deterministischer, weniger kreativ.
                                  # Für Klassifizierung wollen wir das.
            "num_predict": 1024,  # Maximale Tokens in der Antwort
        },
    }

    timeout = aiohttp.ClientTimeout(total=OLLAMA_TIMEOUT)

    try:
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{OLLAMA_BASE_URL}/api/chat",
                json=payload,
                headers={"Content-Type": "application/json"},
            ) as response:
                if response.status != 200:
                    error_text = await response.text()
                    raise ConnectionError(
                        f"Ollama antwortete mit Status {response.status}: {error_text}"
                    )
                data = await response.json()
                return data["message"]["content"]

    except aiohttp.ClientConnectorError:
        raise ConnectionError(
            "Ollama ist nicht erreichbar. "
            "Bitte starte Ollama mit: `ollama serve`"
        )


# ── JSON-Extraktion aus LLM-Antworten ─────────────────────────────────────────
def _extract_json(text: str) -> Any:
    """
    LLMs geben manchmal JSON in Markdown-Blöcken zurück:
    ```json
    [{"id": 1, ...}]
    ```
    Diese Funktion extrahiert den reinen JSON-String, egal wie das Modell
    ihn verpackt hat. Robustheit ist hier wichtiger als Eleganz.
    """
    text = text.strip()

    # Markdown-Code-Block entfernen falls vorhanden
    match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if match:
        text = match.group(1).strip()

    # Direktes Parsen versuchen
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # Letzter Versuch: ersten JSON-Array oder -Object-Block extrahieren
        match = re.search(r"(\[[\s\S]*\]|\{[\s\S]*\})", text)
        if match:
            return json.loads(match.group(1))
        raise ValueError(f"Kein valides JSON in der Antwort gefunden: {text[:200]}")


# ── Kategorisierung ────────────────────────────────────────────────────────────
async def categorize_transactions(
    transactions: list[Transaction],
) -> list[Transaction]:
    """
    Kategorisiert alle Transaktionen durch Aufrufe an Ollama.
    Verarbeitet sie in Batches um den LLM-Kontext nicht zu überfluten.

    Args:
        transactions: Liste von Transaktionen ohne Kategorie.

    Returns:
        Dieselbe Liste, aber jede Transaktion hat jetzt eine Kategorie.
    """
    # Kopie erstellen — wir mutieren nicht das Original (Immutability-Prinzip)
    result = [t.model_copy() for t in transactions]

    # In Batches aufteilen
    batches = [
        result[i : i + BATCH_SIZE] for i in range(0, len(result), BATCH_SIZE)
    ]

    logger.info(
        f"Kategorisiere {len(transactions)} Transaktionen "
        f"in {len(batches)} Batches à {BATCH_SIZE}"
    )

    for batch_idx, batch in enumerate(batches):
        logger.info(f"Verarbeite Batch {batch_idx + 1}/{len(batches)}...")

        # Batch als kompaktes JSON für den Prompt vorbereiten.
        # Wir schicken nur id, description und amount — keine internen Felder.
        batch_input = json.dumps(
            [
                {
                    "id": i,  # lokaler Index im Batch, nicht die DB-ID
                    "description": t.description,
                    "amount": t.amount,
                }
                for i, t in enumerate(batch)
            ],
            ensure_ascii=False,
        )

        try:
            raw_response = await _call_ollama(CATEGORIZE_SYSTEM_PROMPT, batch_input)
            parsed = _extract_json(raw_response)

            # Antwort auf Batch-Transaktionen anwenden
            for item in parsed:
                local_idx = item["id"]
                category = item.get("category", "Sonstiges")

                # Sicherheitsnetz: Kategorie muss in Whitelist sein
                if category not in VALID_CATEGORIES:
                    logger.warning(
                        f"LLM gab ungültige Kategorie '{category}' zurück → 'Sonstiges'"
                    )
                    category = "Sonstiges"

                if 0 <= local_idx < len(batch):
                    batch[local_idx] = batch[local_idx].model_copy(
                        update={"category": category}
                    )

        except (ValueError, KeyError) as e:
            # Wenn ein Batch fehlschlägt, loggen und mit "Sonstiges" weitermachen.
            # Besser eine teilweise Kategorisierung als gar keine.
            logger.error(f"Batch {batch_idx + 1} fehlgeschlagen: {e}")
            for t in batch:
                if t.category is None:
                    t = t.model_copy(update={"category": "Sonstiges"})

    return result


# ── Insights generieren ────────────────────────────────────────────────────────
async def generate_insights(request: InsightRequest) -> InsightResponse:
    """
    Schickt die aggregierten Finanzdaten ans LLM und bekommt strukturierte
    Tipps zurück. Wichtig: Wir schicken NUR die Zusammenfassung, nie
    die Rohtransaktionen. Das schützt die Privatsphäre und hält den
    Prompt kurz.
    """
    analysis = request.analysis

    # Kompakte Zusammenfassung für den Prompt bauen
    categories_text = "\n".join(
        f"  - {c.category}: {c.total:.2f}€ ({c.percentage:.1f}%)"
        for c in sorted(analysis.categories, key=lambda x: x.total, reverse=True)
    )

    user_message = f"""Analysiere folgende Finanzdaten und gib Tipps:

Zeitraum: {analysis.period_start} bis {analysis.period_end}
Gesamteinnahmen: {analysis.total_income:.2f}€
Gesamtausgaben: {analysis.total_expenses:.2f}€
Saldo: {analysis.net:.2f}€

Ausgaben pro Kategorie:
{categories_text}
"""

    if request.user_context:
        user_message += f"\nKontext vom Nutzer: {request.user_context}"

    try:
        raw_response = await _call_ollama(INSIGHTS_SYSTEM_PROMPT, user_message)
        parsed = _extract_json(raw_response)

        return InsightResponse(
            summary=parsed.get("summary", "Keine Zusammenfassung verfügbar."),
            warnings=parsed.get("warnings", []),
            tips=parsed.get("tips", []),
            positive=parsed.get("positive", []),
        )

    except (ValueError, KeyError) as e:
        logger.error(f"Insights-Generierung fehlgeschlagen: {e}")
        # Fallback: leere aber valide Antwort
        return InsightResponse(
            summary="Analyse konnte nicht generiert werden. Bitte versuche es erneut.",
            warnings=[],
            tips=[],
            positive=[],
        )


# ── Health Check ───────────────────────────────────────────────────────────────
async def check_ollama_health() -> dict[str, str]:
    """Prüft ob Ollama läuft und das Modell verfügbar ist."""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{OLLAMA_BASE_URL}/api/tags",
                timeout=aiohttp.ClientTimeout(total=5),
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    models = [m["name"] for m in data.get("models", [])]
                    if any(OLLAMA_MODEL in m for m in models):
                        return {"status": "ok", "model": OLLAMA_MODEL}
                    return {
                        "status": "model_missing",
                        "message": f"Modell '{OLLAMA_MODEL}' nicht gefunden. "
                                   f"Bitte ausführen: ollama pull {OLLAMA_MODEL}",
                    }
    except Exception as e:
        return {"status": "unreachable", "message": str(e)}