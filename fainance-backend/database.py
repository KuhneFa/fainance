import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Generator, Optional

from models import AnalysisResult, CategorySummary, InsightResponse, Transaction

DB_PATH = Path(__file__).parent / "finance.db"


@contextmanager
def get_connection() -> Generator[sqlite3.Connection, None, None]:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db() -> None:
    """Erstellt alle Tabellen falls nicht vorhanden."""
    with get_connection() as conn:
        init_insights_table(conn)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS transactions (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                date        TEXT    NOT NULL,
                description TEXT    NOT NULL,
                amount      REAL    NOT NULL,
                category    TEXT,
                upload_id   TEXT    NOT NULL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS upload_sessions (
                id          TEXT PRIMARY KEY,
                filename    TEXT NOT NULL,
                uploaded_at TEXT NOT NULL,
                row_count   INTEGER NOT NULL
            )
        """)
        # Insights werden gecacht — nicht bei jedem Aufruf neu generiert.
        # Ein Upload hat genau einen Insights-Eintrag.
        conn.execute("""
            CREATE TABLE IF NOT EXISTS insights (
                upload_id   TEXT PRIMARY KEY,
                summary     TEXT NOT NULL,
                warnings    TEXT NOT NULL,
                tips        TEXT NOT NULL,
                positive    TEXT NOT NULL,
                generated_at TEXT NOT NULL
            )
        """)


# ── Schreiben ──────────────────────────────────────────────────────────────────
def save_upload_session(
    session_id: str, filename: str, uploaded_at: str, row_count: int
) -> None:
    with get_connection() as conn:
        conn.execute(
            """
            INSERT INTO upload_sessions (id, filename, uploaded_at, row_count)
            VALUES (?, ?, ?, ?)
            """,
            (session_id, filename, uploaded_at, row_count),
        )


def save_transactions(transactions: list[Transaction], upload_id: str) -> None:
    rows = [
        (str(t.date), t.description, t.amount, t.category, upload_id)
        for t in transactions
    ]
    with get_connection() as conn:
        conn.executemany(
            """
            INSERT INTO transactions (date, description, amount, category, upload_id)
            VALUES (?, ?, ?, ?, ?)
            """,
            rows,
        )


def save_insights(upload_id: str, insights: InsightResponse) -> None:
    """
    Speichert Insights für einen Upload.
    Listen werden als pipe-separierte Strings gespeichert — einfacher
    als JSON und ausreichend für unsere Zwecke.
    """
    import json
    with get_connection() as conn:
        conn.execute(
            """
            INSERT OR REPLACE INTO insights
                (upload_id, summary, warnings, tips, positive, generated_at)
            VALUES (?, ?, ?, ?, ?, datetime('now'))
            """,
            (
                upload_id,
                insights.summary,
                json.dumps(insights.warnings, ensure_ascii=False),
                json.dumps(insights.tips, ensure_ascii=False),
                json.dumps(insights.positive, ensure_ascii=False),
            ),
        )


def update_transaction_category(transaction_id: int, category: str) -> None:
    with get_connection() as conn:
        conn.execute(
            "UPDATE transactions SET category = ? WHERE id = ?",
            (category, transaction_id),
        )


# ── Lesen ──────────────────────────────────────────────────────────────────────
def get_transactions(upload_id: str) -> list[Transaction]:
    with get_connection() as conn:
        rows = conn.execute(
            "SELECT * FROM transactions WHERE upload_id = ? ORDER BY date DESC",
            (upload_id,),
        ).fetchall()
    return [
        Transaction(
            id=row["id"],
            date=row["date"],
            description=row["description"],
            amount=row["amount"],
            category=row["category"],
        )
        for row in rows
    ]


def get_analysis(upload_id: str) -> AnalysisResult:
    """Aggregiert Ausgaben direkt in SQL."""
    with get_connection() as conn:
        totals = conn.execute(
            """
            SELECT
                COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0)
                    AS income,
                COALESCE(SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END), 0)
                    AS expenses,
                MIN(date) AS period_start,
                MAX(date) AS period_end
            FROM transactions
            WHERE upload_id = ?
            """,
            (upload_id,),
        ).fetchone()

        cat_rows = conn.execute(
            """
            SELECT
                COALESCE(category, 'Sonstiges') AS category,
                SUM(amount)                      AS total,
                COUNT(*)                         AS count
            FROM transactions
            WHERE upload_id = ? AND amount < 0
            GROUP BY category
            ORDER BY total ASC
            """,
            (upload_id,),
        ).fetchall()

    total_expenses = abs(totals["expenses"])
    categories = [
        CategorySummary(
            category=row["category"],
            total=abs(row["total"]),
            count=row["count"],
            percentage=round(abs(row["total"]) / total_expenses * 100, 1)
            if total_expenses > 0
            else 0.0,
        )
        for row in cat_rows
    ]

    return AnalysisResult(
        total_income=round(totals["income"], 2),
        total_expenses=round(total_expenses, 2),
        net=round(totals["income"] + totals["expenses"], 2),
        categories=categories,
        period_start=totals["period_start"],
        period_end=totals["period_end"],
    )


def get_cached_insights(upload_id: str) -> Optional[InsightResponse]:
    """Gibt gecachte Insights zurück, oder None wenn noch keine vorhanden."""
    import json
    with get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM insights WHERE upload_id = ?",
            (upload_id,),
        ).fetchone()

    if row is None:
        return None

    return InsightResponse(
        summary=row["summary"],
        warnings=json.loads(row["warnings"]),
        tips=json.loads(row["tips"]),
        positive=json.loads(row["positive"]),
    )


# ── Insights Cache ─────────────────────────────────────────────────────────────
def init_insights_table(conn: sqlite3.Connection) -> None:
    """Insights-Tabelle erstellen — wird von init_db() aufgerufen."""
    conn.execute("""
        CREATE TABLE IF NOT EXISTS insights_cache (
            upload_id   TEXT PRIMARY KEY,
            summary     TEXT NOT NULL,
            warnings    TEXT NOT NULL,  -- JSON-Array als String
            tips        TEXT NOT NULL,  -- JSON-Array als String
            positive    TEXT NOT NULL,  -- JSON-Array als String
            created_at  TEXT NOT NULL
        )
    """)


def save_insights(upload_id: str, insights) -> None:
    """Speichert generierte Insights im Cache."""
    import json
    from datetime import datetime, timezone

    with get_connection() as conn:
        conn.execute("""
            INSERT OR REPLACE INTO insights_cache
                (upload_id, summary, warnings, tips, positive, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (
            upload_id,
            insights.summary,
            json.dumps(insights.warnings, ensure_ascii=False),
            json.dumps(insights.tips, ensure_ascii=False),
            json.dumps(insights.positive, ensure_ascii=False),
            datetime.now(timezone.utc).isoformat(),
        ))


def get_cached_insights(upload_id: str):
    """Gibt gecachte Insights zurück, oder None wenn nicht vorhanden."""
    import json
    from models import InsightResponse

    with get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM insights_cache WHERE upload_id = ?",
            (upload_id,),
        ).fetchone()

    if row is None:
        return None

    return InsightResponse(
        summary=row["summary"],
        warnings=json.loads(row["warnings"]),
        tips=json.loads(row["tips"]),
        positive=json.loads(row["positive"]),
    )