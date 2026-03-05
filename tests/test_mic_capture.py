import time
import numpy as np
import pytest
from unittest.mock import patch, MagicMock
from audio.mic_capture import MicCapture


class TestMicCapture:
    def test_init_starts_stream(self):
        with patch("audio.mic_capture.sd") as mock_sd:
            mock_stream = MagicMock()
            mock_sd.InputStream.return_value = mock_stream
            mic = MicCapture()
            mock_sd.InputStream.assert_called_once()
            mock_stream.start.assert_called_once()

    def test_start_clears_chunks_and_sets_recording(self):
        with patch("audio.mic_capture.sd"):
            mic = MicCapture()
            mic.start()
            assert mic.is_recording is True

    def test_stop_returns_empty_when_no_audio(self):
        with patch("audio.mic_capture.sd"):
            mic = MicCapture()
            mic.start()
            audio = mic.stop()
            assert isinstance(audio, np.ndarray)
            assert audio.size == 0
            assert mic.is_recording is False

    def test_callback_stores_chunks_when_recording(self):
        with patch("audio.mic_capture.sd"):
            mic = MicCapture()
            mic.start()
            # Simulate audio callback
            fake_audio = np.random.randn(1024, 1).astype(np.float32)
            mic._callback(fake_audio, 1024, None, None)
            mic._callback(fake_audio, 1024, None, None)
            audio = mic.stop()
            assert audio.size == 2048

    def test_callback_ignores_when_not_recording(self):
        with patch("audio.mic_capture.sd"):
            mic = MicCapture()
            # Not recording — callback should discard
            fake_audio = np.random.randn(1024, 1).astype(np.float32)
            mic._callback(fake_audio, 1024, None, None)
            mic.start()
            audio = mic.stop()
            assert audio.size == 0

    def test_stop_flattens_to_1d(self):
        with patch("audio.mic_capture.sd"):
            mic = MicCapture()
            mic.start()
            fake_audio = np.ones((512, 1), dtype=np.float32)
            mic._callback(fake_audio, 512, None, None)
            audio = mic.stop()
            assert audio.ndim == 1
            assert audio.shape == (512,)
