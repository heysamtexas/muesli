import time
import numpy as np
import wave
from transcribe.engine import transcribe as transcribe_audio, _log


def transcribe_wav(wav_path: str) -> list[dict]:
    """Transcribe a WAV file and return timestamped segments.

    Returns list of {"start": float, "end": float, "text": str}
    """
    _log(f"[batch] Transcribing {wav_path}...")
    t0 = time.time()

    # Read WAV file into numpy array
    with wave.open(wav_path, "r") as wf:
        n_frames = wf.getnframes()
        sample_rate = wf.getframerate()
        n_channels = wf.getnchannels()
        sample_width = wf.getsampwidth()
        raw = wf.readframes(n_frames)

    # Convert to float32 numpy array
    if sample_width == 2:
        audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    elif sample_width == 4:
        audio = np.frombuffer(raw, dtype=np.int32).astype(np.float32) / 2147483648.0
    else:
        audio = np.frombuffer(raw, dtype=np.float32)

    # Mix to mono if stereo
    if n_channels == 2:
        audio = audio.reshape(-1, 2).mean(axis=1)

    # Resample to 16kHz if needed
    if sample_rate != 16000:
        from scipy.signal import resample
        n_samples = int(len(audio) * 16000 / sample_rate)
        audio = resample(audio, n_samples).astype(np.float32)

    duration = len(audio) / 16000
    _log(f"[batch] Audio: {duration:.1f}s, transcribing...")

    # Transcribe in chunks for timestamps
    chunk_duration = 30  # seconds per chunk
    chunk_size = 16000 * chunk_duration
    segments = []

    for i in range(0, len(audio), chunk_size):
        chunk = audio[i : i + chunk_size]
        if len(chunk) < 1600:  # skip very short chunks (< 0.1s)
            continue
        start_time = i / 16000
        text = transcribe_audio(chunk)
        if text:
            segments.append({
                "start": start_time,
                "end": start_time + len(chunk) / 16000,
                "text": text,
            })

    elapsed = time.time() - t0
    _log(f"[batch] Done: {len(segments)} segments in {elapsed:.1f}s ({duration/elapsed:.1f}x realtime)")
    return segments
