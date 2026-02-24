from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from app.db.conn import get_conn

router = APIRouter(prefix="/v1/analytics", tags=["analytics"])


class CategoryTotal(BaseModel):
    category: str
    expense_cents: int  # positive Zahl


class SummaryResponse(BaseModel):
    from_date: str | None
    to_date: str | None
    income_cents: int
    expense_cents: int  # positive Zahl
    net_cents: int
    by_category: list[CategoryTotal]


@router.get("/summary", response_model=SummaryResponse)
def summary(from_date: str | None = None, to_date: str | None = None) -> SummaryResponse:
    where = []
    params: list[object] = []

    if from_date:
        where.append("booking_date >= ?")
        params.append(from_date)
    if to_date:
        where.append("booking_date <= ?")
        params.append(to_date)

    where_sql = ("WHERE " + " AND ".join(where)) if where else ""

    conn = get_conn()
    try:
        # income: amount_cents > 0
        row_income = conn.execute(
            f"SELECT COALESCE(SUM(amount_cents), 0) AS s FROM transactions {where_sql} AND amount_cents > 0"
            if where_sql else
            "SELECT COALESCE(SUM(amount_cents), 0) AS s FROM transactions WHERE amount_cents > 0",
            params,
        ).fetchone()
        income_cents = int(row_income["s"])

        # expense: amount_cents < 0 (store as positive)
        row_expense = conn.execute(
            f"SELECT COALESCE(SUM(-amount_cents), 0) AS s FROM transactions {where_sql} AND amount_cents < 0"
            if where_sql else
            "SELECT COALESCE(SUM(-amount_cents), 0) AS s FROM transactions WHERE amount_cents < 0",
            params,
        ).fetchone()
        expense_cents = int(row_expense["s"])

        # net: sum(amount_cents) (can be negative)
        row_net = conn.execute(
            f"SELECT COALESCE(SUM(amount_cents), 0) AS s FROM transactions {where_sql}",
            params,
        ).fetchone()
        net_cents = int(row_net["s"])

        # category totals (expenses only)
        rows = conn.execute(
            f"""
            SELECT category, COALESCE(SUM(-amount_cents), 0) AS expense_cents
            FROM transactions
            {where_sql}
            AND amount_cents < 0
            GROUP BY category
            ORDER BY expense_cents DESC
            """,
            params,
        ).fetchall() if where_sql else conn.execute(
            """
            SELECT category, COALESCE(SUM(-amount_cents), 0) AS expense_cents
            FROM transactions
            WHERE amount_cents < 0
            GROUP BY category
            ORDER BY expense_cents DESC
            """
        ).fetchall()

        by_category = [CategoryTotal(category=r["category"], expense_cents=int(r["expense_cents"])) for r in rows]

        return SummaryResponse(
            from_date=from_date,
            to_date=to_date,
            income_cents=income_cents,
            expense_cents=expense_cents,
            net_cents=net_cents,
            by_category=by_category,
        )
    finally:
        conn.close()
class TimeseriesPoint(BaseModel):
    period: str  # YYYY-MM
    income_cents: int
    expense_cents: int
    net_cents: int

class TimeseriesResponse(BaseModel):
    from_date: str | None
    to_date: str | None
    points: list[TimeseriesPoint]

@router.get("/timeseries", response_model=TimeseriesResponse)
def timeseries(from_date: str | None = None, to_date: str | None = None, interval: str = "month") -> TimeseriesResponse:
    where = []
    params: list[object] = []
    if interval not in ("day", "week", "month"):
        interval = "month"
    if interval == "day":
        period_expr = "substr(booking_date, 1, 10)"  # YYYY-MM-DD
    elif interval == "week":
        # week starts Monday-ish: use year-week from date
        period_expr = "strftime('%Y-W%W', booking_date)"
    else:
        period_expr = "substr(booking_date, 1, 7)"   # YYYY-MM

    if from_date:
        where.append("booking_date >= ?")
        params.append(from_date)
    if to_date:
        where.append("booking_date <= ?")
        params.append(to_date)
    where_sql = ("WHERE " + " AND ".join(where)) if where else ""

    conn = get_conn()
    try:
        rows = conn.execute(
            f"""
            SELECT
              {period_expr} AS period,
              COALESCE(SUM(CASE WHEN amount_cents > 0 THEN amount_cents ELSE 0 END), 0) AS income_cents,
              COALESCE(SUM(CASE WHEN amount_cents < 0 THEN -amount_cents ELSE 0 END), 0) AS expense_cents,
              COALESCE(SUM(amount_cents), 0) AS net_cents
            FROM transactions
            {where_sql}
            GROUP BY period
            ORDER BY period ASC
            """,
            params
        ).fetchall()

        points = [
            TimeseriesPoint(
                period=r["period"],
                income_cents=int(r["income_cents"]),
                expense_cents=int(r["expense_cents"]),
                net_cents=int(r["net_cents"]),
            )
            for r in rows
        ]

        return TimeseriesResponse(from_date=from_date, to_date=to_date, points=points)
    finally:
        conn.close()
class RangeResponse(BaseModel):
    min_date: str | None
    max_date: str | None

@router.get("/range", response_model=RangeResponse)
def date_range() -> RangeResponse:
    conn = get_conn()
    try:
        row = conn.execute(
            "SELECT MIN(booking_date) AS min_date, MAX(booking_date) AS max_date FROM transactions"
        ).fetchone()
        return RangeResponse(min_date=row["min_date"], max_date=row["max_date"])
    finally:
        conn.close()
