"""Event log for secrets operations with undo support (SQLite-backed, append-only)."""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class LogEntry:
    """A single operation in the history log."""

    id: int
    timestamp: str
    operation: str
    name: str
    backend: str
    backup: str | None = None


class History:
    """Event log manager using SQLite with Type 2 append-only pattern."""

    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.db_path = data_dir / "history.db"
        self._init_db()

    def _init_db(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    operation TEXT NOT NULL,
                    name TEXT NOT NULL,
                    backend TEXT NOT NULL,
                    backup TEXT
                )
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_delete_with_backup
                ON events (operation, id DESC)
                WHERE operation = 'delete' AND backup IS NOT NULL
            """)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)

    def _timestamp(self) -> str:
        return datetime.now(timezone.utc).isoformat()

    def log(
        self,
        operation: str,
        name: str,
        backend: str,
        backup: str | None = None,
    ) -> None:
        """Append an operation to the event log."""
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO events (timestamp, operation, name, backend, backup)
                VALUES (?, ?, ?, ?, ?)
                """,
                (self._timestamp(), operation, name, backend, backup),
            )
            conn.commit()

    def get_last_delete(self) -> LogEntry | None:
        """Get the most recent delete operation with backup that hasn't been undone."""
        with self._connect() as conn:
            cursor = conn.execute(
                """
                SELECT d.id, d.timestamp, d.operation, d.name, d.backend, d.backup
                FROM events d
                WHERE d.operation = 'delete'
                  AND d.backup IS NOT NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM events u
                    WHERE u.operation = 'undo'
                      AND u.name = d.name
                      AND u.id > d.id
                  )
                ORDER BY d.id DESC
                LIMIT 1
                """
            )
            row = cursor.fetchone()
            if row is None:
                return None
            return LogEntry(
                id=row[0],
                timestamp=row[1],
                operation=row[2],
                name=row[3],
                backend=row[4],
                backup=row[5],
            )

    def entries(self) -> list[LogEntry]:
        """Get all log entries in chronological order."""
        with self._connect() as conn:
            cursor = conn.execute(
                """
                SELECT id, timestamp, operation, name, backend, backup
                FROM events
                ORDER BY id ASC
                """
            )
            return [
                LogEntry(
                    id=row[0],
                    timestamp=row[1],
                    operation=row[2],
                    name=row[3],
                    backend=row[4],
                    backup=row[5],
                )
                for row in cursor.fetchall()
            ]

    def is_empty(self) -> bool:
        """Check if the event log has no entries."""
        with self._connect() as conn:
            cursor = conn.execute("SELECT 1 FROM events LIMIT 1")
            return cursor.fetchone() is None
