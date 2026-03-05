import sqlite3
import os
import json
from datetime import datetime

DB_DIR = os.path.expanduser("~/Library/Application Support/Muesli")
DB_PATH = os.path.join(DB_DIR, "muesli.db")


def _get_conn() -> sqlite3.Connection:
    os.makedirs(DB_DIR, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db():
    """Create tables if they don't exist."""
    conn = _get_conn()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS meetings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            calendar_event_id TEXT,
            start_time TEXT NOT NULL,
            end_time TEXT,
            duration_seconds REAL,
            raw_transcript TEXT,
            formatted_notes TEXT,
            mic_audio_path TEXT,
            system_audio_path TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS dictations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            duration_seconds REAL,
            raw_text TEXT,
            app_context TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
    """)
    conn.commit()
    conn.close()
    print(f"[db] Initialized at {DB_PATH}")


def save_meeting(
    title: str,
    start_time: datetime,
    end_time: datetime,
    raw_transcript: str,
    formatted_notes: str,
    calendar_event_id: str = None,
    mic_audio_path: str = None,
    system_audio_path: str = None,
) -> int:
    """Save a meeting record. Returns the meeting ID."""
    duration = (end_time - start_time).total_seconds()
    conn = _get_conn()
    cursor = conn.execute(
        """INSERT INTO meetings
           (title, calendar_event_id, start_time, end_time, duration_seconds,
            raw_transcript, formatted_notes, mic_audio_path, system_audio_path)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            title,
            calendar_event_id,
            start_time.isoformat(),
            end_time.isoformat(),
            duration,
            raw_transcript,
            formatted_notes,
            mic_audio_path,
            system_audio_path,
        ),
    )
    conn.commit()
    meeting_id = cursor.lastrowid
    conn.close()
    print(f"[db] Saved meeting #{meeting_id}: {title} ({duration:.0f}s)")
    return meeting_id


def get_recent_meetings(limit: int = 10) -> list[dict]:
    """Get the most recent meetings."""
    conn = _get_conn()
    rows = conn.execute(
        "SELECT * FROM meetings ORDER BY start_time DESC LIMIT ?", (limit,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def save_dictation(text: str, duration: float, app_context: str = ""):
    """Save a dictation record."""
    conn = _get_conn()
    conn.execute(
        "INSERT INTO dictations (timestamp, duration_seconds, raw_text, app_context) VALUES (?, ?, ?, ?)",
        (datetime.now().isoformat(), duration, text, app_context),
    )
    conn.commit()
    conn.close()
