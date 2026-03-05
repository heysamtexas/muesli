import sys
import threading
import time
import numpy as np

_model_lock = threading.Lock()
_transcribe_fn = None
_last_used: float = 0.0
_unload_timer: threading.Timer | None = None
_ready = threading.Event()

MODEL_REPO = "mlx-community/whisper-small.en-mlx"
IDLE_TIMEOUT = 120  # seconds before unloading model


def _log(msg):
    print(msg, flush=True)
    sys.stdout.flush()


def _ensure_loaded():
    global _transcribe_fn, _last_used
    with _model_lock:
        if _transcribe_fn is None:
            _log(f"[transcribe] Loading model {MODEL_REPO}...")
            t0 = time.time()
            import mlx_whisper
            from mlx_whisper import transcribe as _mlx_transcribe
            # Load model weights by importing the model explicitly
            from mlx_whisper.load_models import load_model
            load_model(MODEL_REPO)
            _transcribe_fn = _mlx_transcribe
            _ready.set()
            _log(f"[transcribe] Model ready in {time.time() - t0:.1f}s")
        _last_used = time.time()
        _schedule_unload()


def _schedule_unload():
    global _unload_timer
    if _unload_timer:
        _unload_timer.cancel()
    _unload_timer = threading.Timer(IDLE_TIMEOUT, _try_unload)
    _unload_timer.daemon = True
    _unload_timer.start()


def _try_unload():
    global _transcribe_fn, _unload_timer
    with _model_lock:
        if time.time() - _last_used >= IDLE_TIMEOUT:
            _log("[transcribe] Unloading model (idle timeout)")
            _transcribe_fn = None
            _ready.clear()
            _unload_timer = None


def preload():
    """Pre-load the model at startup so first transcription is instant."""
    _ensure_loaded()


def transcribe(audio: np.ndarray) -> str:
    """Transcribe a numpy audio array (16kHz float32 mono) to text."""
    if audio.size == 0:
        return ""
    _ensure_loaded()
    t0 = time.time()
    result = _transcribe_fn(audio, path_or_hf_repo=MODEL_REPO)
    _log(f"[transcribe] Transcribed in {time.time() - t0:.1f}s")
    return result.get("text", "").strip()
