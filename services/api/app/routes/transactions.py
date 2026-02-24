from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.db.conn import get_conn

router = APIRouter(prefix="/v1/transactions", tags=["transactions"])

class TransactionOut(BaseModel):
    id: str
    booking_date: str
    amount_cents: int
    currency: str
    description: str
    merchant: str | None
    category: str

class TransactionsPage(BaseModel):
    items: list[TransactionOut]
    page: int
    page_size: int
    total: int

class TransactionPatch(BaseModel):
    category: str = Field(min_length=1, max_length=64)

@router.get("")
def list_transactions(
    page: int = 1,
    page_size: int = 50,
    category: str | None = None,
    q: str | None = None,
    from_date: str | None = None,
    to_date: str | None = None,
) -> TransactionsPage:
    page = max(page, 1)
    page_size = min(max(page_size, 1), 200)
    offset = (page - 1) * page_size

    where = []
    params: list[object] = []

    if category:
        where.append("category = ?")
        params.append(category)
    if q:
        where.append("(description LIKE ? OR merchant LIKE ?)")
        params.extend([f"%{q}%", f"%{q}%"])
    if from_date:
        where.append("booking_date >= ?")
        params.append(from_date)
    if to_date:
        where.append("booking_date <= ?")
        params.append(to_date)

    where_sql = ("WHERE " + " AND ".join(where)) if where else ""

    conn = get_conn()
    try:
        total = conn.execute(f"SELECT COUNT(*) as c FROM transactions {where_sql}", params).fetchone()["c"]

        rows = conn.execute(
            f"""
            SELECT id, booking_date, amount_cents, currency, description, merchant, category
            FROM transactions
            {where_sql}
            ORDER BY booking_date DESC
            LIMIT ? OFFSET ?
            """,
            params + [page_size, offset],
        ).fetchall()

        items = [TransactionOut(**dict(r)) for r in rows]
        return TransactionsPage(items=items, page=page, page_size=page_size, total=total)
    finally:
        conn.close()

@router.patch("/{tx_id}", response_model=TransactionOut)
def patch_transaction(tx_id: str, body: TransactionPatch) -> TransactionOut:
    conn = get_conn()
    try:
        cur = conn.execute(
            "UPDATE transactions SET category = ? WHERE id = ?",
            (body.category, tx_id),
        )
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Transaction not found")

        row = conn.execute(
            "SELECT id, booking_date, amount_cents, currency, description, merchant, category FROM transactions WHERE id = ?",
            (tx_id,),
        ).fetchone()
        conn.commit()
        return TransactionOut(**dict(row))
    finally:
        conn.close()
