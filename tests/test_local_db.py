import os
import sqlite3
import tempfile
from datetime import datetime
from unittest.mock import patch
import storage.local_db as db


class TestLocalDB:
    def setup_method(self):
        """Use a temp directory for each test."""
        self._tmpdir = tempfile.mkdtemp()
        self._original_dir = db.DB_DIR
        self._original_path = db.DB_PATH
        db.DB_DIR = self._tmpdir
        db.DB_PATH = os.path.join(self._tmpdir, "test.db")

    def teardown_method(self):
        db.DB_DIR = self._original_dir
        db.DB_PATH = self._original_path
        # Cleanup
        test_db = os.path.join(self._tmpdir, "test.db")
        if os.path.exists(test_db):
            os.remove(test_db)

    def test_init_creates_tables(self):
        db.init_db()
        conn = sqlite3.connect(db.DB_PATH)
        tables = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
        table_names = {t[0] for t in tables}
        assert "meetings" in table_names
        assert "dictations" in table_names
        conn.close()

    def test_save_and_get_meeting(self):
        db.init_db()
        start = datetime(2026, 3, 5, 10, 0, 0)
        end = datetime(2026, 3, 5, 10, 30, 0)
        meeting_id = db.save_meeting(
            title="Test Meeting",
            start_time=start,
            end_time=end,
            raw_transcript="You: hello\nOthers: hi",
            formatted_notes="# Test Meeting\n\nSummary here",
        )
        assert meeting_id == 1

        meetings = db.get_recent_meetings(limit=5)
        assert len(meetings) == 1
        assert meetings[0]["title"] == "Test Meeting"
        assert meetings[0]["duration_seconds"] == 1800.0

    def test_save_dictation(self):
        db.init_db()
        db.save_dictation("hello world", duration=2.5, app_context="terminal")
        conn = sqlite3.connect(db.DB_PATH)
        rows = conn.execute("SELECT * FROM dictations").fetchall()
        assert len(rows) == 1
        conn.close()

    def test_multiple_meetings_ordered_by_recent(self):
        db.init_db()
        for i in range(3):
            db.save_meeting(
                title=f"Meeting {i}",
                start_time=datetime(2026, 3, 5, 10 + i, 0, 0),
                end_time=datetime(2026, 3, 5, 10 + i, 30, 0),
                raw_transcript=f"transcript {i}",
                formatted_notes=f"notes {i}",
            )
        meetings = db.get_recent_meetings(limit=2)
        assert len(meetings) == 2
        assert meetings[0]["title"] == "Meeting 2"  # most recent first
