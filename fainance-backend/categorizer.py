import logging
import re
from typing import Optional

import aiohttp

from models import Transaction, InsightRequest, InsightResponse, VALID_CATEGORIES

logger = logging.getLogger(__name__)

OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "llama3.2:3b"
BATCH_SIZE = 15
OLLAMA_TIMEOUT = 120


# ── Keyword-Matching ───────────────────────────────────────────────────────────
# Erste Verteidigungslinie — schnell, offline, deterministisch.
# Trifft ~80% aller alltäglichen Transaktionen korrekt.
KEYWORD_RULES: list[tuple[str, list[str]]] = [
    ("Miete", [
        "miete", "warmmiete", "kaltmiete", "nebenkosten", "hausgeld",
        "wohnungsmiete", "mietüberweisung",
    ]),
    ("Sparen / Investieren", [
        "sparplan", "etf", "depot", "investition", "aktien", "fondssparplan",
        "trade republic", "scalable", "comdirect depot", "ing-diba depot",
        "tagesgeld", "festgeld",
    ]),
    ("Lebensmittel", [
        "rewe", "edeka", "aldi", "lidl", "penny", "netto", "kaufland",
        "real", "tegut", "norma", "nahkauf", "supermarkt", "lebensmittel",
        "backerei", "bäckerei", "metzgerei", "bioladen", "denns",
    ]),
    ("Drogerie", [
        "dm ", "dm-", " dm\t", "rossmann", "müller drogerie", "budni",
        "drogerie", "douglas", "parfümerie",
    ]),
    ("Sport", [
        "fitnessstudio", "fitness", "mcfit", "clever fit", "planet fitness",
        "sportstudio", "sportverein", "schwimmbad", "tennis", "fußball",
        "yoga", "pilates", "decathlon", "intersport",
    ]),
    ("Transport", [
        "deutsche bahn", "db bahn", "mvv", "hvv", "bvg", "rheinbahn", "vbb",
        "tankstelle", "shell", "aral", "esso", "total energie", "jet tankstelle",
        "uber", "taxi", "flixbus", "fernbus", "parken", "parkhaus", "maut",
    ]),
    ("Unterhaltung", [
        "netflix", "spotify", "amazon prime", "disney+", "apple tv",
        "youtube premium", "dazn", "sky ", "maxdome", "joyn",
        "kino", "cinema", "theater", "konzert", "steam", "playstation",
    ]),
    ("Gesundheit", [
        "apotheke", "arzt", "arztpraxis", "krankenhaus", "klinik",
        "zahnarzt", "physiotherapie", "optiker", "sanitätshaus", "zuzahlung",
    ]),
    ("Versicherungen", [
        "versicherung", "allianz", "huk", "axa", "ergo", "signal iduna",
        "debeka", "techniker krankenkasse", "barmer", "aok", "dak",
        "haftpflicht", "kfz-versicherung",
    ]),
    ("Freizeit & Freunde", [
        "restaurant", "gasthaus", "cafe ", "café", "bar ", "bistro",
        "vapiano", "mcdonalds", "burger king", "subway", "pizza",
        "lieferando", "uber eats", "wolt",
    ]),
    ("Geschenke", [
        "geschenk", "blumen", "florist", "thalia", "weltbild",
        "hugendubel", "mayersche",
    ]),
]


def categorize_by_keywords(description: str) -> Optional[str]:
    """
    Gibt eine Kategorie zurück wenn ein Keyword matched, sonst None.
    None bedeutet: LLM soll entscheiden.
    """
    desc_lower = description.lower()
    for category, keywords in KEYWORD_RULES:
        for keyword in keywords:
            if keyword in desc_lower:
                return category
    return None


# ── LLM-Fallback via /api/generate ────────────────────────────────────────────
# Wir nutzen /api/generate statt /api/chat — stabiler bei kleineren Modellen.
# Der Prompt ist so kurz wie möglich: eine Transaktion, eine Antwort.
CATEGORIES_COMPACT = ", ".join(sorted(VALID_CATEGORIES))

async def _ask_llm_for_category(description: str, amount: float) -> str:
    """
    Fragt das LLM nach der Kategorie einer einzelnen Transaktion.
    Wird nur aufgerufen wenn Keyword-Matching nichts gefunden hat.
    """
    prompt = (
        f"Categorize this German bank transaction into exactly one category.\n"
        f"Transaction: {description} ({amount:+.2f}€)\n"
        f"Categories: {CATEGORIES_COMPACT}\n"
        f"Answer with ONLY the category name, nothing else:"
    )

    payload = {
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.0, "num_predict": 20},
    }

    timeout = aiohttp.ClientTimeout(total=OLLAMA_TIMEOUT)
    try:
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{OLLAMA_BASE_URL}/api/generate",
                json=payload,
            ) as response:
                if response.status != 200:
                    return "Sonstiges"
                data = await response.json()
                raw = data.get("response", "").strip()
                return _match_category(raw)
    except Exception as e:
        logger.warning(f"LLM-Aufruf fehlgeschlagen für '{description}': {e}")
        return "Sonstiges"


def _match_category(raw: str) -> str:
    """
    Fuzzy-Match: findet die beste gültige Kategorie im LLM-Output.
    Das Modell schreibt manchmal "Lebensmittel." oder "1. Lebensmittel"
    — wir bereinigen und matchen.
    """
    # Sonderzeichen und Nummerierungen entfernen
    cleaned = re.sub(r"^\d+[\.\)]\s*", "", raw.strip())
    cleaned = cleaned.split("\n")[0].strip()  # nur erste Zeile

    # Exakter Match
    if cleaned in VALID_CATEGORIES:
        return cleaned

    # Case-insensitive Match
    for cat in VALID_CATEGORIES:
        if cat.lower() == cleaned.lower():
            return cat

    # Partial Match — Kategorie im Text enthalten
    for cat in VALID_CATEGORIES:
        if cat.lower() in cleaned.lower():
            return cat

    logger.warning(f"Kein Match für LLM-Antwort: '{raw}' → Sonstiges")
    return "Sonstiges"


# ── Haupt-Kategorisierung ──────────────────────────────────────────────────────
async def categorize_transactions(
    transactions: list[Transaction],
) -> list[Transaction]:
    """
    Hybrid-Ansatz:
    1. Keywords → sofortige Kategorisierung für bekannte Händler (~80%)
    2. LLM → für alles was Keywords nicht kennen (~20%)
    3. Einnahmen → immer "Sonstiges", kein LLM-Call nötig
    """
    result = [t.model_copy() for t in transactions]

    # Zuerst alle per Keyword kategorisieren
    keyword_count = 0
    llm_needed: list[int] = []  # Indizes die das LLM brauchen

    for i, t in enumerate(result):
        # Einnahmen brauchen kein LLM
        if t.amount > 0:
            result[i] = t.model_copy(update={"category": "Sonstiges"})
            keyword_count += 1
            continue

        category = categorize_by_keywords(t.description)
        if category:
            result[i] = t.model_copy(update={"category": category})
            keyword_count += 1
            logger.info(f"Keyword: {t.description[:35]:<35} → {category}")
        else:
            llm_needed.append(i)

    logger.info(
        f"Keywords: {keyword_count}/{len(transactions)} kategorisiert. "
        f"LLM benötigt für: {len(llm_needed)} Transaktionen."
    )

    # LLM nur für unbekannte Transaktionen
    for i in llm_needed:
        t = result[i]
        category = await _ask_llm_for_category(t.description, t.amount)
        result[i] = t.model_copy(update={"category": category})
        logger.info(f"LLM:     {t.description[:35]:<35} → {category}")

    return result


# ── Insights ───────────────────────────────────────────────────────────────────
async def generate_insights(request: InsightRequest) -> InsightResponse:
    """
    LLM gibt Spartipps basierend auf aggregierten Ausgaben.
    Kein Zugriff auf Rohtransaktionen — nur Kategorie-Summaries.
    """
    analysis = request.analysis

    categories_text = "\n".join(
        f"- {c.category}: {c.total:.2f}€ ({c.percentage:.1f}%)"
        for c in sorted(analysis.categories, key=lambda x: x.total, reverse=True)
    )

    prompt = (
        f"Du bist ein Finanzberater." 
        f"Analysiere diese Ausgaben." 
        f"Antworte auf Deutsch.\n\n"
        f"Zeitraum: {analysis.period_start} bis {analysis.period_end}\n"
        f"Einnahmen: {analysis.total_income:.2f}€\n"
        f"Ausgaben: {analysis.total_expenses:.2f}€\n"
        f"Saldo: {analysis.net:.2f}€\n\n"
        f"Ausgaben:\n{categories_text}\n\n"
        f"Antworte in diesem Format:\n"
        f"ZUSAMMENFASSUNG: <2 Sätze>\n"
        f"WARNUNG: <Kategorie wo zu viel ausgegeben wird>\n"
        f"WARNUNG: <zweite Warnung falls nötig>\n"
        f"TIPP: <konkreter Spartipp>\n"
        f"TIPP: <weiterer Tipp>\n"
        f"POSITIV: <was gut läuft>"
    )
    if request.user_context:
        prompt += f"\nKontext: {request.user_context}"

    payload = {
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.3, "num_predict": 400},
    }

    try:
        timeout = aiohttp.ClientTimeout(total=OLLAMA_TIMEOUT)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{OLLAMA_BASE_URL}/api/generate",
                json=payload,
            ) as response:
                data = await response.json()
                raw = data.get("response", "").strip()
                logger.info(f"Insights: {raw[:300]}")
                return _parse_insights(raw)

    except Exception as e:
        logger.error(f"Insights fehlgeschlagen: {e}")
        return InsightResponse(
            summary="Analyse nicht verfügbar. Ist Ollama gestartet?",
            warnings=[], tips=[], positive=[],
        )


def _parse_insights(text: str) -> InsightResponse:
    summary, warnings, tips, positive = "", [], [], []

    for line in text.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        upper = line.upper()
        if upper.startswith("ZUSAMMENFASSUNG:"):
            summary = line.split(":", 1)[1].strip()
        elif upper.startswith("WARNUNG:"):
            w = line.split(":", 1)[1].strip()
            if w:
                warnings.append(w)
        elif upper.startswith("TIPP:"):
            t = line.split(":", 1)[1].strip()
            if t:
                tips.append(t)
        elif upper.startswith("POSITIV:"):
            p = line.split(":", 1)[1].strip()
            if p:
                positive.append(p)

    if not summary:
        summary = text[:200]

    return InsightResponse(
        summary=summary,
        warnings=warnings,
        tips=tips,
        positive=positive,
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
                        "message": f"Bitte ausführen: ollama pull {OLLAMA_MODEL}",
                    }
    except Exception as e:
        return {"status": "unreachable", "message": str(e)}