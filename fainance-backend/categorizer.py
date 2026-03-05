import logging
import re
from typing import Any

import aiohttp

from models import Transaction, InsightRequest, InsightResponse, VALID_CATEGORIES

logger = logging.getLogger(__name__)

OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "phi3:mini"
BATCH_SIZE = 15
OLLAMA_TIMEOUT = 120

# Kategorien als nummerierte Liste für den Prompt
CATEGORIES_LIST = "\n".join(
    f"{i+1}. {cat}" for i, cat in enumerate(sorted(VALID_CATEGORIES))
)

# ── Prompts ────────────────────────────────────────────────────────────────────
# Plaintext-Format: viel robuster als JSON für kleinere Modelle.
# Format: "Beschreibung → Kategorie" — eine Zeile pro Transaktion.
CATEGORIZE_SYSTEM_PROMPT = f"""You categorize bank transactions. Reply with ONLY the category name for each transaction.

CATEGORIES:
{CATEGORIES_LIST}

FORMAT: One category per line, in the same order as the input.
- Use ONLY category names from the list above
- Positive amounts are income → always use "Sonstiges"
- If unsure → use "Sonstiges"

EXAMPLE:
Input:
1. REWE SAGT DANKE | -34.50
2. Miete Januar | -850.00
3. Gehalt Februar | +2800.00
4. Fitnessstudio | -29.90

Output:
Lebensmittel
Miete
Sonstiges
Sport"""


INSIGHTS_SYSTEM_PROMPT = """Du bist ein freundlicher Finanzberater. Analysiere die Ausgaben und antworte auf Deutsch.

Struktur deiner Antwort (halte dich genau daran):
ZUSAMMENFASSUNG: <2-3 Sätze zur Gesamtsituation>
WARNUNG: <eine konkrete Warnung wo zu viel ausgegeben wird>
WARNUNG: <optional eine zweite Warnung>
TIPP: <konkreter Spartipp>
TIPP: <weiterer Spartipp>
TIPP: <weiterer Spartipp>
POSITIV: <was gut läuft>
POSITIV: <weiteres Positives>"""


# ── Ollama Client ──────────────────────────────────────────────────────────────
async def _call_ollama(system_prompt: str, user_message: str) -> str:
    payload = {
        "model": OLLAMA_MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
        "stream": False,
        "options": {
            "temperature": 0.1,
            "num_predict": 512,
        },
    }
    timeout = aiohttp.ClientTimeout(total=OLLAMA_TIMEOUT)
    try:
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{OLLAMA_BASE_URL}/api/chat",
                json=payload,
            ) as response:
                if response.status != 200:
                    error_text = await response.text()
                    raise ConnectionError(f"Ollama Status {response.status}: {error_text}")
                data = await response.json()
                return data["message"]["content"]
    except aiohttp.ClientConnectorError:
        raise ConnectionError("Ollama nicht erreichbar. Starte mit: ollama serve")


# ── Plaintext Parser ───────────────────────────────────────────────────────────
def _parse_categories_from_text(text: str, expected_count: int) -> list[str]:
    """
    Parst Kategorien aus dem Plaintext-Output des LLMs.

    Das Modell gibt eine Kategorie pro Zeile zurück:
        Lebensmittel
        Miete
        Sonstiges

    Wir bereinigen jede Zeile und prüfen ob sie in VALID_CATEGORIES ist.
    Falls das Modell weniger Zeilen zurückgibt als erwartet, füllen wir
    mit "Sonstiges" auf.
    """
    # Zeilen aufteilen und bereinigen
    lines = [line.strip() for line in text.strip().splitlines()]

    # Leere Zeilen, Nummern und Pfeile entfernen
    # Modelle schreiben manchmal "1. Lebensmittel" oder "→ Miete"
    cleaned: list[str] = []
    for line in lines:
        if not line:
            continue
        # Nummerierung entfernen: "1. Lebensmittel" → "Lebensmittel"
        line = re.sub(r"^\d+[\.\)]\s*", "", line)
        # Pfeil entfernen: "→ Miete" → "Miete"
        line = re.sub(r"^→\s*", "", line)
        # Alles nach einem | oder : abschneiden (falls Modell zu viel schreibt)
        line = line.split("|")[0].split(":")[0].strip()

        if line:
            cleaned.append(line)

    # Kategorien validieren — ungültige durch "Sonstiges" ersetzen
    categories: list[str] = []
    for line in cleaned[:expected_count]:  # maximal expected_count nehmen
        # Fuzzy-Match: prüfe ob eine gültige Kategorie im Text enthalten ist
        matched = "Sonstiges"
        for valid_cat in VALID_CATEGORIES:
            if valid_cat.lower() in line.lower() or line.lower() in valid_cat.lower():
                matched = valid_cat
                break
        categories.append(matched)

    # Fehlende Kategorien mit Sonstiges auffüllen
    while len(categories) < expected_count:
        categories.append("Sonstiges")

    return categories


def _parse_insights_from_text(text: str) -> dict:
    """
    Parst den strukturierten Insights-Text in ein Dictionary.

    Erwartet Format:
        ZUSAMMENFASSUNG: <text>
        WARNUNG: <text>
        TIPP: <text>
        POSITIV: <text>
    """
    result = {
        "summary": "",
        "warnings": [],
        "tips": [],
        "positive": [],
    }

    for line in text.strip().splitlines():
        line = line.strip()
        if not line:
            continue

        if line.upper().startswith("ZUSAMMENFASSUNG:"):
            result["summary"] = line.split(":", 1)[1].strip()
        elif line.upper().startswith("WARNUNG:"):
            warning = line.split(":", 1)[1].strip()
            if warning:
                result["warnings"].append(warning)
        elif line.upper().startswith("TIPP:"):
            tip = line.split(":", 1)[1].strip()
            if tip:
                result["tips"].append(tip)
        elif line.upper().startswith("POSITIV:"):
            positive = line.split(":", 1)[1].strip()
            if positive:
                result["positive"].append(positive)

    # Fallback falls Zusammenfassung fehlt
    if not result["summary"] and text.strip():
        result["summary"] = text.strip()[:300]

    return result


# ── Kategorisierung ────────────────────────────────────────────────────────────
async def categorize_transactions(transactions: list[Transaction]) -> list[Transaction]:
    result = [t.model_copy() for t in transactions]
    batches = [result[i : i + BATCH_SIZE] for i in range(0, len(result), BATCH_SIZE)]

    logger.info(f"Kategorisiere {len(transactions)} Transaktionen in {len(batches)} Batches")

    for batch_idx, batch in enumerate(batches):
        logger.info(f"Batch {batch_idx + 1}/{len(batches)}...")

        # Einfaches nummeriertes Plaintext-Format
        batch_input = "\n".join(
            f"{i+1}. {t.description} | {t.amount:+.2f}"
            for i, t in enumerate(batch)
        )

        try:
            raw = await _call_ollama(CATEGORIZE_SYSTEM_PROMPT, batch_input)
            logger.info(f"Ollama Antwort (gekürzt): {raw[:200]}")

            categories = _parse_categories_from_text(raw, len(batch))

            for i, category in enumerate(categories):
                batch[i] = batch[i].model_copy(update={"category": category})
                logger.info(f"  {batch[i].description[:30]} → {category}")

        except Exception as e:
            logger.error(f"Batch {batch_idx + 1} fehlgeschlagen: {e}")
            for i in range(len(batch)):
                batch[i] = batch[i].model_copy(update={"category": "Sonstiges"})

    return result


# ── Insights ───────────────────────────────────────────────────────────────────
async def generate_insights(request: InsightRequest) -> InsightResponse:
    analysis = request.analysis

    categories_text = "\n".join(
        f"- {c.category}: {c.total:.2f}€ ({c.percentage:.1f}%)"
        for c in sorted(analysis.categories, key=lambda x: x.total, reverse=True)
    )

    user_message = (
        f"Zeitraum: {analysis.period_start} bis {analysis.period_end}\n"
        f"Einnahmen: {analysis.total_income:.2f}€\n"
        f"Ausgaben: {analysis.total_expenses:.2f}€\n"
        f"Saldo: {analysis.net:.2f}€\n\n"
        f"Ausgaben pro Kategorie:\n{categories_text}"
    )

    if request.user_context:
        user_message += f"\n\nKontext: {request.user_context}"

    try:
        raw = await _call_ollama(INSIGHTS_SYSTEM_PROMPT, user_message)
        logger.info(f"Insights Antwort: {raw[:400]}")
        parsed = _parse_insights_from_text(raw)

        return InsightResponse(
            summary=parsed["summary"] or "Keine Zusammenfassung verfügbar.",
            warnings=parsed["warnings"],
            tips=parsed["tips"],
            positive=parsed["positive"],
        )

    except Exception as e:
        logger.error(f"Insights fehlgeschlagen: {e}")
        return InsightResponse(
            summary="Analyse konnte nicht generiert werden. Ist Ollama gestartet?",
            warnings=[], tips=[], positive=[],
        )


# ── Health Check ───────────────────────────────────────────────────────────────
async def check_ollama_health() -> dict[str, str]:
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
                        "message": f"Modell nicht gefunden. Bitte: ollama pull {OLLAMA_MODEL}",
                    }
    except Exception as e:
        return {"status": "unreachable", "message": str(e)}