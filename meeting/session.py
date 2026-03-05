import threading
import time
import wave
import tempfile
import numpy as np
from datetime import datetime

from audio.mic_capture import MicCapture
from audio.system_capture import SystemCapture
from transcribe.batch import transcribe_wav
from transcribe.engine import transcribe as transcribe_audio
from meeting.transcript import merge_transcripts
from meeting.summary import summarize_transcript
from storage.local_db import save_meeting


class MeetingSession:
    """Orchestrates a meeting recording session: mic + system audio, transcription, summary."""

    def __init__(self, title: str = "Untitled Meeting", calendar_event_id: str = None):
        self.title = title
        self.calendar_event_id = calendar_event_id
        self.mic = MicCapture()
        self.system = SystemCapture()
        self.start_time: datetime | None = None
        self.end_time: datetime | None = None
        self._recording = False
        self._mic_chunks: list[np.ndarray] = []
        self._mic_chunk_lock = threading.Lock()
        self._realtime_thread: threading.Thread | None = None

    def start(self):
        """Start recording from both mic and system audio."""
        self.start_time = datetime.now()
        self._recording = True

        # Start mic capture
        self.mic.start()

        # Start system audio capture
        if self.system.available:
            self.system.start()

        print(f"[meeting] Started: {self.title}")

    def stop(self) -> dict:
        """Stop recording and process everything. Returns meeting data dict."""
        self._recording = False
        self.end_time = datetime.now()
        duration = (self.end_time - self.start_time).total_seconds()
        print(f"[meeting] Stopped: {self.title} ({duration:.0f}s)")

        # Stop and get audio
        mic_audio = self.mic.stop()
        system_wav_path = self.system.stop_to_wav() if self.system.available else None

        # Transcribe mic audio
        mic_segments = []
        if mic_audio.size > 0:
            print("[meeting] Transcribing mic audio...")
            # Save mic to WAV for batch transcription
            mic_wav = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
            with wave.open(mic_wav, "w") as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(16000)
                wf.writeframes((mic_audio * 32767).astype(np.int16).tobytes())
            mic_segments = transcribe_wav(mic_wav)

        # Transcribe system audio
        system_segments = []
        if system_wav_path:
            print("[meeting] Transcribing system audio...")
            system_segments = transcribe_wav(system_wav_path)

        # Merge transcripts
        raw_transcript = merge_transcripts(mic_segments, system_segments, self.start_time)
        print(f"[meeting] Transcript: {len(raw_transcript)} chars")

        # Generate summary via OpenRouter
        formatted_notes = summarize_transcript(raw_transcript, self.title)

        # Save to SQLite
        meeting_id = save_meeting(
            title=self.title,
            start_time=self.start_time,
            end_time=self.end_time,
            raw_transcript=raw_transcript,
            formatted_notes=formatted_notes,
            calendar_event_id=self.calendar_event_id,
        )

        return {
            "id": meeting_id,
            "title": self.title,
            "duration": duration,
            "raw_transcript": raw_transcript,
            "formatted_notes": formatted_notes,
        }

    @property
    def is_recording(self) -> bool:
        return self._recording
