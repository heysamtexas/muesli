import numpy as np
from unittest.mock import patch, MagicMock
import transcribe.engine as engine


class TestTranscribeEngine:
    def test_empty_audio_returns_empty(self):
        result = engine.transcribe(np.array([], dtype=np.float32))
        assert result == ""

    @patch("transcribe.engine._ensure_loaded")
    def test_transcribe_calls_model(self, mock_load):
        engine._transcribe_fn = MagicMock(return_value={"text": " Hello world "})
        result = engine.transcribe(np.zeros(16000, dtype=np.float32))
        assert result == "Hello world"
        engine._transcribe_fn.assert_called_once()
        # Cleanup
        engine._transcribe_fn = None

    @patch("transcribe.engine._ensure_loaded")
    def test_transcribe_strips_whitespace(self, mock_load):
        engine._transcribe_fn = MagicMock(return_value={"text": "  spaced out  "})
        result = engine.transcribe(np.ones(16000, dtype=np.float32))
        assert result == "spaced out"
        engine._transcribe_fn = None

    @patch("transcribe.engine._ensure_loaded")
    def test_transcribe_handles_empty_result(self, mock_load):
        engine._transcribe_fn = MagicMock(return_value={"text": ""})
        result = engine.transcribe(np.ones(16000, dtype=np.float32))
        assert result == ""
        engine._transcribe_fn = None
