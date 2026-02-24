from __future__ import annotations
import sqlite3
from pathlib import Path
from app.core.settings import DB_PATH

BASE_DIR = Path(__file__).resolve().parent
SCHEMA_PATH = BASE_DIR / "schema.sql"
SEED_PATH = BASE_DIR / "seed.sql"

def _exec_sql_file(conn: sqlite3.Connection, path: Path) -> None:
    conn.executescript(path.read_text(encoding="utf-8"))

def init_db() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("PRAGMA foreign_keys=ON;")
        conn.execute("PRAGMA journal_mode=WAL;")

        _exec_sql_file(conn, SCHEMA_PATH)

        (count,) = conn.execute("SELECT COUNT(*) FROM category_rules;").fetchone()
        if count == 0 and SEED_PATH.exists():
            _exec_sql_file(conn, SEED_PATH)

        conn.commit()
    finally:
        conn.close()
