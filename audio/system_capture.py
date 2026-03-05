import threading
import wave
import tempfile
import numpy as np
import objc
from Foundation import NSObject
import ScreenCaptureKit


class _AudioDelegate(NSObject):
    """Delegate that receives audio samples from SCStream."""

    def init(self):
        self = objc.super(_AudioDelegate, self).init()
        if self is None:
            return None
        self.chunks = []
        self.lock = threading.Lock()
        self.recording = False
        return self

    def stream_didOutputSampleBuffer_ofType_(self, stream, sample_buffer, output_type):
        # output_type 1 = audio
        if output_type != 1 or not self.recording:
            return
        try:
            # Get audio buffer from CMSampleBuffer
            block_buffer = ScreenCaptureKit.CMSampleBufferGetDataBuffer(sample_buffer)
            if block_buffer is None:
                return
            length = ScreenCaptureKit.CMBlockBufferGetDataLength(block_buffer)
            if length == 0:
                return

            # Get raw bytes
            data = bytes(length)
            status = ScreenCaptureKit.CMBlockBufferCopyDataBytes(
                block_buffer, 0, length, data
            )
            if status != 0:
                return

            # Convert to float32 numpy (ScreenCaptureKit gives us float32 PCM)
            audio = np.frombuffer(data, dtype=np.float32)
            with self.lock:
                if self.recording:
                    self.chunks.append(audio.copy())
        except Exception as e:
            print(f"[system_audio] Callback error: {e}")


class SystemCapture:
    """Captures system audio via ScreenCaptureKit.

    Requires Screen Recording permission (macOS will prompt on first use).
    """

    SAMPLE_RATE = 16000
    CHANNELS = 1

    def __init__(self):
        self._delegate = _AudioDelegate.alloc().init()
        self._stream = None
        self._available = True
        print("[system_audio] Using ScreenCaptureKit (permission-based)")

    @property
    def available(self) -> bool:
        return self._available

    def start(self):
        """Start capturing system audio."""
        self._delegate.recording = True
        with self._delegate.lock:
            self._delegate.chunks.clear()

        def _setup():
            try:
                # Get shareable content (triggers permission prompt if needed)
                event = threading.Event()
                content_result = [None]
                error_result = [None]

                def content_handler(content, error):
                    content_result[0] = content
                    error_result[0] = error
                    event.set()

                ScreenCaptureKit.SCShareableContent.getShareableContentExcludingDesktopWindows_onScreenWindowsOnly_completionHandler_(
                    True, True, content_handler
                )
                event.wait(timeout=10)

                if error_result[0]:
                    print(f"[system_audio] Permission error: {error_result[0]}")
                    self._available = False
                    return

                content = content_result[0]
                if content is None:
                    print("[system_audio] No shareable content available")
                    self._available = False
                    return

                # Create a display filter (capture all audio)
                displays = content.displays()
                if not displays or len(displays) == 0:
                    print("[system_audio] No displays found")
                    self._available = False
                    return

                display = displays[0]
                content_filter = ScreenCaptureKit.SCContentFilter.alloc().initWithDisplay_excludingWindows_(
                    display, []
                )

                # Configure stream for audio only
                config = ScreenCaptureKit.SCStreamConfiguration.alloc().init()
                config.setCapturesAudio_(True)
                config.setExcludesCurrentProcessAudio_(True)
                config.setSampleRate_(self.SAMPLE_RATE)
                config.setChannelCount_(self.CHANNELS)

                # Minimize video overhead since we only want audio
                config.setWidth_(1)
                config.setHeight_(1)
                config.setMinimumFrameInterval_(ScreenCaptureKit.CMTimeMake(1, 1))  # 1 fps minimum

                # Create and start stream
                self._stream = ScreenCaptureKit.SCStream.alloc().initWithFilter_configuration_delegate_(
                    content_filter, config, None
                )

                # Add audio output
                error = None
                queue = ScreenCaptureKit.dispatch_get_global_queue(0, 0)
                success = self._stream.addStreamOutput_type_sampleHandlerQueue_error_(
                    self._delegate, 1, queue, None  # type 1 = audio
                )

                # Start capture
                start_event = threading.Event()
                start_error = [None]

                def start_handler(error):
                    start_error[0] = error
                    start_event.set()

                self._stream.startCaptureWithCompletionHandler_(start_handler)
                start_event.wait(timeout=10)

                if start_error[0]:
                    print(f"[system_audio] Start error: {start_error[0]}")
                    self._available = False
                else:
                    print("[system_audio] Recording system audio via ScreenCaptureKit")

            except Exception as e:
                print(f"[system_audio] Setup error: {e}")
                self._available = False

        threading.Thread(target=_setup, daemon=True).start()

    def stop(self) -> np.ndarray:
        """Stop recording and return audio as numpy array."""
        self._delegate.recording = False

        if self._stream:
            stop_event = threading.Event()

            def stop_handler(error):
                if error:
                    print(f"[system_audio] Stop error: {error}")
                stop_event.set()

            self._stream.stopCaptureWithCompletionHandler_(stop_handler)
            stop_event.wait(timeout=5)
            self._stream = None

        with self._delegate.lock:
            if not self._delegate.chunks:
                return np.array([], dtype=np.float32)
            audio = np.concatenate(self._delegate.chunks)
            # Mix to mono if needed
            if audio.ndim > 1:
                audio = audio.mean(axis=1)
            self._delegate.chunks.clear()
            return audio.astype(np.float32)

    def stop_to_wav(self) -> str | None:
        """Stop recording and save to a temporary WAV file."""
        audio = self.stop()
        if audio.size == 0:
            return None
        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        with wave.open(tmp.name, "w") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(self.SAMPLE_RATE)
            wf.writeframes((audio * 32767).astype(np.int16).tobytes())
        duration = len(audio) / self.SAMPLE_RATE
        print(f"[system_audio] Saved {duration:.1f}s to {tmp.name}")
        return tmp.name

    @property
    def is_recording(self) -> bool:
        return self._delegate.recording
