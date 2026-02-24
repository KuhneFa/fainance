from pydantic import BaseModel, field_validator
from datetime import date
from typing import Optional


# ── Kategorien ────────────────────────────────────────────────────────────────
# Wir verwenden eine feste Liste, damit das LLM nicht halluziniert
# und immer in eine dieser Kategorien einsortiert.
VALID_CATEGORIES = {
    "Lebensmittel",
    "Miete",
    "Sparen / Investieren",
    "Drogerie",
    "Sport",
    "Freizeit & Freunde",
    "Geschenke",
    "Transport",
    "Versicherungen",
    "Gesundheit",
    "Unterhaltung",
    "Sonstiges",
}


# ── Einzelne Transaktion ───────────────────────────────────────────────────────
class Transaction(BaseModel):
    """
    Repräsentiert eine einzelne Kontobewegung nach dem Parsen der CSV.
    Optional-Felder können fehlen, z.B. wenn die Bank sie nicht liefert.
    """

    id: Optional[int] = None          # wird von SQLite vergeben
    date: date                        # Buchungsdatum
    description: str                  # Verwendungszweck / Empfänger
    amount: float                     # negativ = Ausgabe, positiv = Einnahme
    category: Optional[str] = None    # wird später vom Kategorisierer gesetzt

    @field_validator("amount")
    @classmethod
    def amount_must_be_nonzero(cls, v: float) -> float:
        if v == 0.0:
            raise ValueError("Betrag darf nicht 0 sein.")
        return round(v, 2)  # auf Cent runden

    @field_validator("category")
    @classmethod
    def category_must_be_valid(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_CATEGORIES:
            raise ValueError(
                f"'{v}' ist keine gültige Kategorie. "
                f"Erlaubt: {sorted(VALID_CATEGORIES)}"
            )
        return v


# ── Analyse-Zusammenfassung ────────────────────────────────────────────────────
class CategorySummary(BaseModel):
    """
    Aggregation aller Ausgaben pro Kategorie.
    Das ist das Objekt, das ans LLM geschickt wird — niemals Rohdaten!
    """

    category: str
    total: float        # Summe in Euro
    count: int          # Anzahl Transaktionen
    percentage: float   # Anteil an Gesamtausgaben in %


class AnalysisResult(BaseModel):
    """
    Vollständiges Ergebnis einer Analyse-Session.
    Wird vom /analysis Endpoint zurückgegeben und im Flutter-Dashboard angezeigt.
    """

    total_income: float
    total_expenses: float
    net: float                          # Einnahmen - Ausgaben
    categories: list[CategorySummary]
    period_start: date
    period_end: date


# ── LLM Insights ──────────────────────────────────────────────────────────────
class InsightRequest(BaseModel):
    """
    Payload für den /insights Endpoint.
    Das Frontend schickt die aggregierten Daten, nicht die Rohtransaktionen.
    """

    analysis: AnalysisResult
    user_context: Optional[str] = None  # z.B. "Ich bin Student mit Nebenjob"


class InsightResponse(BaseModel):
    """
    Antwort des LLM, aufgeteilt in strukturierte Felder.
    So kann Flutter die Tipps sauber darstellen.
    """

    summary: str            # kurze Zusammenfassung der Finanzsituation
    warnings: list[str]     # Kategorien wo zu viel ausgegeben wird
    tips: list[str]         # konkrete Spartipps
    positive: list[str]     # was gut läuft (Motivation!)