import threading
import numpy as np
import sounddevice as sd


class MicCapture:
    """Captures audio from the microphone. Stream stays open for zero-latency start."""

    SAMPLE_RATE = 16000
    CHANNELS = 1
    DTYPE = "float32"
    BLOCK_SIZE = 1024

    def __init__(self):
        self._chunks: list[np.ndarray] = []
        self._lock = threading.Lock()
        self._recording = False
        # Open stream immediately — always listening, only saves when recording
        self._stream = sd.InputStream(
            samplerate=self.SAMPLE_RATE,
            channels=self.CHANNELS,
            dtype=self.DTYPE,
            blocksize=self.BLOCK_SIZE,
            callback=self._callback,
        )
        self._stream.start()

    def _callback(self, indata, frames, time_info, status):
        if status:
            print(f"[mic] {status}")
        with self._lock:
            if self._recording:
                self._chunks.append(indata.copy())

    def start(self):
        with self._lock:
            self._chunks.clear()
            self._recording = True

    def stop(self) -> np.ndarray:
        with self._lock:
            self._recording = False
            if not self._chunks:
                return np.array([], dtype=np.float32)
            audio = np.concatenate(self._chunks, axis=0).flatten()
            self._chunks.clear()
            return audio

    @property
    def is_recording(self) -> bool:
        return self._recording
