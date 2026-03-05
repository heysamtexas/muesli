import threading
from pynput import keyboard


class HoldToRecord:
    """Hold left Cmd to record. If another key is pressed while Cmd is held,
    it's treated as a shortcut (Cmd+C etc.) and recording is not triggered."""

    HOLD_DELAY = 0.15  # seconds before Cmd-hold triggers recording

    def __init__(self, on_start, on_stop):
        self._on_start = on_start
        self._on_stop = on_stop
        self._cmd_held = False
        self._other_key_pressed = False
        self._active = False
        self._timer: threading.Timer | None = None
        self._listener: keyboard.Listener | None = None

    def _on_press(self, key):
        if key == keyboard.Key.cmd or key == keyboard.Key.cmd_l:
            if not self._cmd_held:
                self._cmd_held = True
                self._other_key_pressed = False
                # Start a timer — if no other key is pressed within HOLD_DELAY, start recording
                self._timer = threading.Timer(self.HOLD_DELAY, self._maybe_start)
                self._timer.daemon = True
                self._timer.start()
        elif self._cmd_held:
            # Another key pressed while Cmd held → it's a shortcut, cancel
            self._other_key_pressed = True
            if self._timer:
                self._timer.cancel()
                self._timer = None
            # If already recording (rare edge case), stop it
            if self._active:
                self._active = False
                threading.Thread(target=self._on_stop, daemon=True).start()

    def _maybe_start(self):
        if self._cmd_held and not self._other_key_pressed and not self._active:
            self._active = True
            threading.Thread(target=self._on_start, daemon=True).start()

    def _on_release(self, key):
        if key == keyboard.Key.cmd or key == keyboard.Key.cmd_l:
            self._cmd_held = False
            if self._timer:
                self._timer.cancel()
                self._timer = None
            if self._active:
                self._active = False
                threading.Thread(target=self._on_stop, daemon=True).start()

    def start(self):
        self._listener = keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release,
        )
        self._listener.daemon = True
        self._listener.start()

    def stop(self):
        if self._listener:
            self._listener.stop()
            self._listener = None

    @property
    def is_active(self) -> bool:
        return self._active
