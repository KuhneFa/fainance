"""
insights.py — Strukturierte Finanzanalyse mit LLM-Unterstützung.

Trennung von Verantwortlichkeiten:
- insights.py: Analyse-Logik, Benchmarks, Prompt-Aufbau
- categorizer.py: Kategorisierung von Transaktionen
"""
import logging
from dataclasses import dataclass

import aiohttp

from models import AnalysisResult, CategorySummary, InsightRequest, InsightResponse

logger = logging.getLogger(__name__)

OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "llama3.2:3b"
OLLAMA_TIMEOUT = 120

# ── Benchmarks ─────────────────────────────────────────────────────────────────
# Typische Ausgabenanteile eines deutschen Singlehaushalts (Destatis 2023).
# Quelle: Statistisches Bundesamt, Einkommens- und Verbrauchsstichprobe.
# Werte in Prozent des Nettoeinkommens.
CATEGORY_BENCHMARKS: dict[str, float] = {
    "Miete": 30.0,
    "Lebensmittel": 14.0,
    "Transport": 8.0,
    "Freizeit & Freunde": 7.0,
    "Versicherungen": 6.0,
    "Unterhaltung": 4.0,
    "Drogerie": 3.0,
    "Gesundheit": 3.0,
    "Sport": 2.0,
    "Sparen / Investieren": 10.0,
    "Geschenke": 2.0,
    "Sonstiges": 5.0,
}

# Kategorien wo Überschreitung besonders wichtig ist
HIGH_PRIORITY_CATEGORIES = {
    "Freizeit & Freunde",
    "Unterhaltung",
    "Lebensmittel",
    "Transport",
}


@dataclass
class CategoryInsight:
    """Analyse einer einzelnen Kategorie im Vergleich zum Benchmark."""
    category: str
    actual_pct: float       # tatsächlicher Anteil am Einkommen
    benchmark_pct: float    # Richtwert
    actual_amount: float    # Betrag in Euro
    deviation: float        # Abweichung in Prozentpunkten (positiv = zu viel)
    is_over_budget: bool


def analyze_categories(analysis: AnalysisResult) -> list[CategoryInsight]:
    """
    Vergleicht jede Kategorie mit dem Benchmark.
    Basis ist das Nettoeinkommen (total_income).
    Falls kein Einkommen vorhanden, nehmen wir die Gesamtausgaben als Basis.
    """
    base = analysis.total_income if analysis.total_income > 0 \
        else analysis.total_expenses

    insights = []
    for cat in analysis.categories:
        benchmark = CATEGORY_BENCHMARKS.get(cat.category, 5.0)
        actual_pct = (cat.total / base * 100) if base > 0 else 0
        deviation = actual_pct - benchmark

        insights.append(CategoryInsight(
            category=cat.category,
            actual_pct=round(actual_pct, 1),
            benchmark_pct=benchmark,
            actual_amount=cat.total,
            deviation=round(deviation, 1),
            is_over_budget=deviation > 2.0,  # >2% über Benchmark = Warnung
        ))

    # Größte Überschreitungen zuerst
    return sorted(insights, key=lambda x: x.deviation, reverse=True)


def _build_prompt(request: InsightRequest, insights: list[CategoryInsight]) -> str:
    """
    Baut einen strukturierten Prompt der dem LLM alle nötigen Infos gibt.
    Klare Struktur → bessere, konsistentere Antworten.
    """
    analysis = request.analysis

    # Überschreitungen zusammenfassen
    over_budget = [i for i in insights if i.is_over_budget]
    under_budget = [
        i for i in insights
        if i.deviation < -3.0 and i.category == "Sparen / Investieren"
    ]

    over_text = "\n".join(
        f"  - {i.category}: {i.actual_pct:.1f}% "
        f"(Richtwert: {i.benchmark_pct:.1f}%, "
        f"+{i.deviation:.1f}% über Benchmark, "
        f"{i.actual_amount:.2f}€)"
        for i in over_budget[:4]  # max 4 Warnungen
    ) or "  Keine Kategorien über dem Richtwert."

    all_cats = "\n".join(
        f"  - {i.category}: {i.actual_amount:.2f}€ "
        f"({i.actual_pct:.1f}% vom Einkommen, "
        f"Richtwert: {i.benchmark_pct:.1f}%)"
        for i in insights
    )

    savings_rate = (
        (analysis.net / analysis.total_income * 100)
        if analysis.total_income > 0 else 0
    )

    prompt = (
        f"Du bist ein ehrlicher, konstruktiver Finanzberater. "
        f"Analysiere diese Finanzdaten eines deutschen Haushalts.\n\n"
        f"ZEITRAUM: {analysis.period_start} bis {analysis.period_end}\n"
        f"EINNAHMEN: {analysis.total_income:.2f}€\n"
        f"AUSGABEN: {analysis.total_expenses:.2f}€\n"
        f"SALDO: {analysis.net:.2f}€\n"
        f"SPARQUOTE: {savings_rate:.1f}%\n\n"
        f"KATEGORIEN (mit Vergleich zu Richtwerten):\n{all_cats}\n\n"
        f"KATEGORIEN ÜBER RICHTWERT:\n{over_text}\n"
    )

    if under_budget:
        prompt += (
            f"\nSPAREN UNTER RICHTWERT: "
            f"Nur {under_budget[0].actual_pct:.1f}% gespart "
            f"(Empfehlung: {under_budget[0].benchmark_pct:.1f}%)\n"
        )

    if request.user_context:
        prompt += f"\nKONTEXT VOM NUTZER: {request.user_context}\n"

    prompt += (
        f"\nAntworte auf Deutsch in genau diesem Format "
        f"(jede Zeile beginnt mit dem Label):\n"
        f"ZUSAMMENFASSUNG: <2 präzise Sätze zur Gesamtsituation>\n"
        f"WARNUNG: <konkrete Kategorie mit Betrag wo zu viel ausgegeben wird>\n"
        f"WARNUNG: <zweite Warnung falls relevant, sonst weglassen>\n"
        f"TIPP: <konkreter umsetzbarer Spartipp mit Beispiel>\n"
        f"TIPP: <weiterer Tipp>\n"
        f"TIPP: <weiterer Tipp>\n"
        f"POSITIV: <was gut läuft, mit konkretem Bezug zu den Zahlen>\n"
    )

    return prompt


def _parse_response(text: str) -> InsightResponse:
    """Parst den strukturierten LLM-Output zeilenweise."""
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

    if not summary and text.strip():
        # Fallback: erste Zeile als Zusammenfassung
        summary = text.strip().splitlines()[0][:200]

    return InsightResponse(
        summary=summary,
        warnings=warnings,
        tips=tips,
        positive=positive,
    )


async def generate_insights(
    analysis: AnalysisResult,
    user_context: str | None = None,
) -> InsightResponse:
    """
    Hauptfunktion: Analysiert Finanzdaten und generiert LLM-Insights.

    Flow:
    1. Kategorien gegen Benchmarks vergleichen (lokal, kein LLM)
    2. Strukturierten Prompt bauen
    3. LLM aufrufen
    4. Antwort parsen
    """
    # Schritt 1 & 2: Lokale Analyse + Prompt
    request = InsightRequest(analysis=analysis, user_context=user_context)
    category_insights = analyze_categories(analysis)
    prompt = _build_prompt(request, category_insights)

    logger.info(
        f"Insights generieren für Zeitraum "
        f"{analysis.period_start} – {request.analysis.period_end}, "
        f"{len(category_insights)} Kategorien, "
        f"{len([i for i in category_insights if i.is_over_budget])} Überschreitungen"
    )

    # Schritt 3: LLM aufrufen
    payload = {
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": 0.3,
            "num_predict": 500,
        },
    }

    try:
        timeout = aiohttp.ClientTimeout(total=OLLAMA_TIMEOUT)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{OLLAMA_BASE_URL}/api/generate",
                json=payload,
            ) as response:
                if response.status != 200:
                    raise ConnectionError(
                        f"Ollama Status {response.status}"
                    )
                data = await response.json()
                raw = data.get("response", "").strip()
                logger.info(f"LLM Antwort: {raw[:300]}")

                # Schritt 4: Parsen
                result = _parse_response(raw)

                # Fallback: wenn LLM keine Warnungen gibt, nehmen wir
                # die lokale Analyse
                if not result.warnings and category_insights:
                    top = category_insights[0]
                    if top.is_over_budget:
                        result.warnings.append(
                            f"{top.category}: {top.actual_amount:.2f}€ "
                            f"({top.actual_pct:.1f}% statt "
                            f"{top.benchmark_pct:.1f}% Richtwert)"
                        )

                return result

    except ConnectionError as e:
        logger.error(f"Ollama nicht erreichbar: {e}")
        # Auch ohne LLM geben wir nützliche Insights zurück
        return _fallback_insights(category_insights, request.analysis)

    except Exception as e:
        logger.error(f"Insights fehlgeschlagen: {e}")
        return _fallback_insights(category_insights, request.analysis)


def _fallback_insights(
    insights: list[CategoryInsight],
    analysis: AnalysisResult,
) -> InsightResponse:
    """
    Regel-basierte Insights wenn Ollama nicht verfügbar ist.
    Kein LLM nötig — nützlich für CI und Offline-Nutzung.
    """
    warnings = [
        f"{i.category}: {i.actual_amount:.2f}€ "
        f"({i.actual_pct:.1f}% vom Einkommen, "
        f"Richtwert: {i.benchmark_pct:.1f}%)"
        for i in insights if i.is_over_budget
    ][:3]

    savings_rate = (
        analysis.net / analysis.total_income * 100
        if analysis.total_income > 0 else 0
    )

    tips = []
    if savings_rate < 10:
        tips.append(
            "Deine Sparquote liegt unter 10%. "
            "Versuche mindestens 10% des Einkommens zu sparen."
        )
    for i in insights:
        if i.is_over_budget and i.category in HIGH_PRIORITY_CATEGORIES:
            tips.append(
                f"Bei {i.category} könntest du "
                f"{i.deviation:.0f}% einsparen "
                f"(ca. {i.actual_amount * i.deviation / 100:.0f}€/Monat)."
            )
    if not tips:
        tips.append("Behalte deine Ausgaben im Blick und setze dir ein Budget.")

    positive = []
    if savings_rate >= 15:
        positive.append(
            f"Sehr gute Sparquote von {savings_rate:.1f}%!"
        )
    if analysis.net > 0:
        positive.append(
            f"Du lebst unter deinen Verhältnissen — "
            f"{analysis.net:.2f}€ Überschuss."
        )

    summary = (
        f"Im Zeitraum {analysis.period_start} bis {analysis.period_end} "
        f"hast du {analysis.total_expenses:.2f}€ ausgegeben bei "
        f"{analysis.total_income:.2f}€ Einnahmen "
        f"(Sparquote: {savings_rate:.1f}%)."
    )

    return InsightResponse(
        summary=summary,
        warnings=warnings,
        tips=tips or ["Halte deine Ausgaben im Blick."],
        positive=positive or ["Deine Finanzdaten wurden erfolgreich analysiert."],
    )