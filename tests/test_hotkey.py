import time
import threading
from unittest.mock import MagicMock, patch
from pynput import keyboard
from dictation.hotkey import HoldToRecord


class TestHoldToRecord:
    def test_cmd_hold_triggers_start(self):
        on_start = MagicMock()
        on_stop = MagicMock()
        htr = HoldToRecord(on_start, on_stop)

        # Simulate Cmd press
        htr._on_press(keyboard.Key.cmd)
        # Wait for hold delay
        time.sleep(0.25)
        assert on_start.called

    def test_cmd_quick_release_no_trigger(self):
        on_start = MagicMock()
        on_stop = MagicMock()
        htr = HoldToRecord(on_start, on_stop)

        # Simulate quick Cmd press + release (faster than HOLD_DELAY)
        htr._on_press(keyboard.Key.cmd)
        time.sleep(0.05)
        htr._on_release(keyboard.Key.cmd)
        time.sleep(0.2)
        assert not on_start.called

    def test_cmd_plus_other_key_cancels(self):
        on_start = MagicMock()
        on_stop = MagicMock()
        htr = HoldToRecord(on_start, on_stop)

        # Simulate Cmd+C (shortcut — should NOT trigger recording)
        htr._on_press(keyboard.Key.cmd)
        time.sleep(0.05)
        htr._on_press(keyboard.KeyCode.from_char("c"))
        time.sleep(0.2)
        assert not on_start.called

    def test_release_triggers_stop(self):
        on_start = MagicMock()
        on_stop = MagicMock()
        htr = HoldToRecord(on_start, on_stop)

        htr._on_press(keyboard.Key.cmd)
        time.sleep(0.25)  # wait for hold delay
        assert on_start.called
        # Now release
        htr._on_release(keyboard.Key.cmd)
        time.sleep(0.1)
        assert on_stop.called

    def test_is_active_reflects_state(self):
        htr = HoldToRecord(lambda: None, lambda: None)
        assert htr.is_active is False

        htr._on_press(keyboard.Key.cmd)
        time.sleep(0.25)
        assert htr.is_active is True

        htr._on_release(keyboard.Key.cmd)
        time.sleep(0.1)
        assert htr.is_active is False
