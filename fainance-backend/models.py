from datetime import date
from typing import Optional

from pydantic import BaseModel, field_validator

# ── Kategorien ────────────────────────────────────────────────────────────────
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


class Transaction(BaseModel):
    id: Optional[int] = None
    date: date
    description: str
    amount: float
    category: Optional[str] = None

    @field_validator("amount")
    @classmethod
    def amount_must_be_nonzero(cls, v: float) -> float:
        if v == 0.0:
            raise ValueError("Betrag darf nicht 0 sein.")
        return round(v, 2)

    @field_validator("category")
    @classmethod
    def category_must_be_valid(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_CATEGORIES:
            raise ValueError(
                f"'{v}' ist keine gültige Kategorie. "
                f"Erlaubt: {sorted(VALID_CATEGORIES)}"
            )
        return v


class CategorySummary(BaseModel):
    category: str
    total: float
    count: int
    percentage: float


class AnalysisResult(BaseModel):
    total_income: float
    total_expenses: float
    net: float
    categories: list[CategorySummary]
    period_start: date
    period_end: date


class InsightRequest(BaseModel):
    analysis: AnalysisResult
    user_context: Optional[str] = None


class InsightResponse(BaseModel):
    summary: str
    warnings: list[str]
    tips: list[str]
    positive: list[str]