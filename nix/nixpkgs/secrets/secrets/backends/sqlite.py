"""SQLite backend for secrets storage (primarily for testing)."""

import sqlite3
from pathlib import Path

from .base import Backend


class SQLiteBackend(Backend):
    """SQLite-based secrets storage backend."""

    name = "sqlite"

    def __init__(self, db_path: str | Path):
        self.db_path = Path(db_path)
        self._init_db()

    def _init_db(self) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS secrets (
                    name TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                )
                """
            )
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)

    def get(self, name: str) -> str | None:
        with self._connect() as conn:
            cursor = conn.execute("SELECT value FROM secrets WHERE name = ?", (name,))
            row = cursor.fetchone()
            return row[0] if row else None

    def store(self, name: str, value: str) -> None:
        with self._connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO secrets (name, value) VALUES (?, ?)",
                (name, value),
            )
            conn.commit()

    def delete(self, name: str) -> bool:
        with self._connect() as conn:
            cursor = conn.execute("DELETE FROM secrets WHERE name = ?", (name,))
            conn.commit()
            return cursor.rowcount > 0

    def list(self) -> list[str]:
        with self._connect() as conn:
            cursor = conn.execute("SELECT name FROM secrets ORDER BY name")
            return [row[0] for row in cursor.fetchall()]
