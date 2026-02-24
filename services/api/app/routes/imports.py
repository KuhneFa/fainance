from __future__ import annotations

import csv
import hashlib
import io
import json
import re
import sqlite3
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import uuid4

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from app.db.conn import get_conn

router = APIRouter(prefix="/v1/import", tags=["import"])

COMMON_DATE_NAMES = {"date", "datum", "buchungstag", "bookingdate", "valuta", "wertstellung"}
COMMON_AMOUNT_NAMES = {"amount", "betrag", "umsatz", "value"}
COMMON_DESC_NAMES = {"description", "verwendungszweck", "zweck", "text", "buchungstext", "details"}

CATEGORIES = [
    "Lebensmittel","Miete","Sparen/Investieren","Drogerie","Sport","Freunde","Geschenke",
    "Transport","Abos","Essen gehen","Sonstiges","Unkategorisiert"
]

@dataclass
class Detected:
    delimiter: str
    has_header: bool

def _sniff_csv(sample: str) -> Detected:
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=[",", ";", "\t", "|"])
        has_header = csv.Sniffer().has_header(sample)
        return Detected(delimiter=dialect.delimiter, has_header=has_header)
    except Exception:
        return Detected(delimiter=";", has_header=True)

def _normalize_col_name(name: str) -> str:
    return name.strip().lower()

def _suggest_mapping(columns: list[str]) -> dict[str, str | None]:
    norm = {c: _normalize_col_name(c) for c in columns}
    inv = {v: k for k, v in norm.items()}

    def find_first(candidates: set[str]) -> str | None:
        for cand in candidates:
            if cand in inv:
                return inv[cand]
        for original, n in norm.items():
            for cand in candidates:
                if cand in n:
                    return original
        return None

    return {
        "date": find_first(COMMON_DATE_NAMES),
        "amount": find_first(COMMON_AMOUNT_NAMES),
        "description": find_first(COMMON_DESC_NAMES),
    }

def _parse_date(s: str) -> str:
    s = (s or "").strip()
    for fmt in ("%Y-%m-%d", "%d.%m.%Y", "%d/%m/%Y", "%d-%m-%Y"):
        try:
            return datetime.strptime(s, fmt).date().isoformat()
        except ValueError:
            pass
    m = re.search(r"\d{4}-\d{2}-\d{2}", s)
    if m:
        return m.group(0)
    raise ValueError(f"unrecognized date: {s}")

def _parse_amount_cents(s: str) -> int:
    s = (s or "").strip().replace("€", "").replace("EUR", "").strip()
    if not s:
        raise ValueError("empty amount")

    if "," in s and "." in s:
        s = s.replace(".", "").replace(",", ".")
    elif "," in s:
        s = s.replace(",", ".")

    neg = False
    if s.startswith("(") and s.endswith(")"):
        neg = True
        s = s[1:-1].strip()
    if s.startswith("-"):
        neg = True
        s = s[1:].strip()

    value = float(s)  # MVP; später Decimal
    cents = int(round(value * 100))
    return -cents if neg else cents

def _extract_merchant(description: str) -> str | None:
    d = (description or "").strip()
    if not d:
        return None
    chunk = re.split(r"[,\|;/]", d)[0].strip()
    return chunk[:80].upper() if chunk else None

def _load_rules(conn) -> list[tuple[str, str, int]]:
    rows = conn.execute(
        "SELECT pattern, category, priority FROM category_rules ORDER BY priority ASC"
    ).fetchall()
    return [(r["pattern"], r["category"], r["priority"]) for r in rows]

def _categorize(description: str, merchant: str | None, rules: list[tuple[str,str,int]]) -> str:
    hay = f"{merchant or ''} {description or ''}".upper()
    for pattern, category, _prio in rules:
        if pattern.upper() in hay:
            return category
    return "Unkategorisiert"

@router.post("/preview")
async def preview_csv(file: UploadFile = File(...)) -> dict[str, Any]:
    raw = await file.read()
    try:
        text = raw.decode("utf-8")
        encoding = "utf-8"
    except UnicodeDecodeError:
        text = raw.decode("latin-1")
        encoding = "latin-1"

    sample = text[:5000]
    detected = _sniff_csv(sample)

    f = io.StringIO(text)
    reader = csv.reader(f, delimiter=detected.delimiter)

    rows: list[list[str]] = []
    for i, row in enumerate(reader):
        if i >= 25:
            break
        rows.append(row)

    if not rows:
        raise HTTPException(status_code=400, detail="Empty CSV")

    if detected.has_header:
        columns = [c.strip() for c in rows[0]]
        data_rows = rows[1:21]
    else:
        max_len = max(len(r) for r in rows[:21])
        columns = [f"col_{i+1}" for i in range(max_len)]
        data_rows = rows[:20]

    out_rows: list[dict[str, str]] = []
    for r in data_rows:
        padded = r + [""] * (len(columns) - len(r))
        out_rows.append({columns[i]: padded[i] for i in range(len(columns))})

    return {
        "detected": {"delimiter": detected.delimiter, "has_header": detected.has_header, "encoding": encoding},
        "columns": columns,
        "rows": out_rows,
        "suggested_mapping": _suggest_mapping(columns),
    }

@router.post("/csv")
async def import_csv(
    file: UploadFile = File(...),
    mapping: str = Form(...),  # JSON string
) -> dict[str, Any]:
    raw = await file.read()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("latin-1")

    try:
        mp = json.loads(mapping)
        date_col = mp["date_col"]
        amount_col = mp["amount_col"]
        description_col = mp["description_col"]
        currency_col = mp.get("currency_col")
        merchant_col = mp.get("merchant_col")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid mapping JSON: {e}")

    detected = _sniff_csv(text[:5000])
    f = io.StringIO(text)
    reader = csv.DictReader(f, delimiter=detected.delimiter)

    received = inserted = skipped = 0
    errors: list[dict[str, str | int]] = []

    now = datetime.utcnow().isoformat(timespec="seconds") + "Z"

    conn = get_conn()
    try:
        rules = _load_rules(conn)

        for row in reader:
            received += 1
            try:
                booking_date = _parse_date(row.get(date_col, ""))
                amount_cents = _parse_amount_cents(row.get(amount_col, ""))
                description = (row.get(description_col, "") or "").strip() or "(no description)"
                currency = ((row.get(currency_col, "") if currency_col else "EUR") or "EUR").strip().upper()[:3]

                merchant = row.get(merchant_col) if merchant_col else None
                merchant = merchant.strip().upper()[:80] if merchant else _extract_merchant(description)

                category = _categorize(description, merchant, rules)

                raw_fingerprint = f"{booking_date}|{amount_cents}|{currency}|{description}|{merchant}"
                raw_hash = hashlib.sha256(raw_fingerprint.encode("utf-8")).hexdigest()

                conn.execute(
                    """
                    INSERT INTO transactions
                    (id, booking_date, amount_cents, currency, description, merchant, category, source, raw_hash, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 'csv', ?, ?)
                    """,
                    (str(uuid4()), booking_date, amount_cents, currency, description, merchant, category, raw_hash, now),
                )
                inserted += 1

            except sqlite3.IntegrityError:
                # duplicate raw_hash
                skipped += 1
            except Exception as e:
                skipped += 1
                if len(errors) < 20:
                    errors.append({
                        "row": received,  # 1-based line within data rows
                        "error": str(e),
                    })

        conn.commit()
    finally:
        conn.close()

    return {
        "rows_received": received,
        "rows_inserted": inserted,
        "rows_skipped_duplicates_or_invalid": skipped,
        "errors": errors,
    }

