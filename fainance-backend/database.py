import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Generator

from models import Transaction, AnalysisResult, CategorySummary

# ── Konfiguration ──────────────────────────────────────────────────────────────
# Die DB-Datei liegt im selben Ordner wie das Backend.
# Path(__file__) ist der absolute Pfad zu dieser Datei (database.py).
DB_PATH = Path(__file__).parent / "finance.db"


# ── Context Manager für Verbindungen ──────────────────────────────────────────
# Ein Context Manager (das `with`-Statement) stellt sicher, dass die
# Datenbankverbindung IMMER geschlossen wird — auch wenn ein Fehler auftritt.
# Das verhindert "connection leaks", die die DB-Datei sperren können.
@contextmanager
def get_connection() -> Generator[sqlite3.Connection, None, None]:
    conn = sqlite3.connect(DB_PATH)
    # Row factory: gibt Zeilen als dict zurück statt als Tuple.
    # So kannst du row["amount"] schreiben statt row[2].
    conn.row_factory = sqlite3.Row
    # Foreign Keys müssen in SQLite explizit aktiviert werden.
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()   # Änderungen speichern wenn alles gut läuft
    except Exception:
        conn.rollback() # Änderungen rückgängig machen bei Fehler
        raise
    finally:
        conn.close()    # Verbindung IMMER schließen


# ── Tabellen anlegen ───────────────────────────────────────────────────────────
def init_db() -> None:
    """
    Erstellt alle Tabellen, falls sie noch nicht existieren.
    Wird beim Start der FastAPI-App aufgerufen.
    `CREATE TABLE IF NOT EXISTS` ist idempotent — kann beliebig oft
    aufgerufen werden ohne Fehler oder Datenverlust.
    """
    with get_connection() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS transactions (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                date        TEXT    NOT NULL,           -- ISO 8601: "2024-03-15"
                description TEXT    NOT NULL,
                amount      REAL    NOT NULL,
                category    TEXT,                       -- NULL bis kategorisiert
                upload_id   TEXT    NOT NULL            -- gruppiert einen CSV-Upload
            )
        """)
        # upload_sessions speichert Metadaten zu jedem CSV-Upload.
        # So kannst du später mehrere Uploads verwalten und vergleichen.
        conn.execute("""
            CREATE TABLE IF NOT EXISTS upload_sessions (
                id          TEXT    PRIMARY KEY,        -- UUID, wird in main.py generiert
                filename    TEXT    NOT NULL,
                uploaded_at TEXT    NOT NULL,           -- ISO 8601 Timestamp
                row_count   INTEGER NOT NULL
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
    """
    Speichert eine Liste von Transaktionen in einem Batch-Insert.
    `executemany` ist deutlich schneller als einzelne INSERT-Statements
    in einer Schleife, weil SQLite nur einmal in die Datei schreibt.
    """
    rows = [
        (
            str(t.date),
            t.description,
            t.amount,
            t.category,
            upload_id,
        )
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


def update_transaction_category(transaction_id: int, category: str) -> None:
    """Wird vom Kategorisierer aufgerufen, nachdem das LLM geantwortet hat."""
    with get_connection() as conn:
        conn.execute(
            "UPDATE transactions SET category = ? WHERE id = ?",
            (category, transaction_id),
        )


# ── Lesen ──────────────────────────────────────────────────────────────────────
def get_transactions(upload_id: str) -> list[Transaction]:
    """Gibt alle Transaktionen eines Uploads zurück."""
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
    """
    Berechnet die Analyse direkt in SQL — das ist effizienter als alle
    Transaktionen zu laden und in Python zu aggregieren.
    SQL ist für genau solche Aggregationen optimiert.
    """
    with get_connection() as conn:
        # Einnahmen und Ausgaben separat summieren
        totals = conn.execute(
            """
            SELECT
                COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) AS income,
                COALESCE(SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END), 0) AS expenses,
                MIN(date) AS period_start,
                MAX(date) AS period_end
            FROM transactions
            WHERE upload_id = ?
            """,
            (upload_id,),
        ).fetchone()

        # Pro-Kategorie aggregieren (nur Ausgaben, d.h. amount < 0)
        cat_rows = conn.execute(
            """
            SELECT
                COALESCE(category, 'Sonstiges') AS category,
                SUM(amount)                      AS total,
                COUNT(*)                         AS count
            FROM transactions
            WHERE upload_id = ? AND amount < 0
            GROUP BY category
            ORDER BY total ASC   -- negativste (größte Ausgabe) zuerst
            """,
            (upload_id,),
        ).fetchall()

    total_expenses = abs(totals["expenses"])  # als positive Zahl für die UI

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