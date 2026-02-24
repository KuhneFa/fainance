from __future__ import annotations
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[2]  # services/api
DB_PATH = (BASE_DIR / "app.db").resolve()
