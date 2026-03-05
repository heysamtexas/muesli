import time
import pyperclip
from pynput.keyboard import Key, Controller

_keyboard = Controller()


def paste_text(text: str):
    """Copy text to clipboard and simulate Cmd+V to paste into the active app."""
    if not text:
        return
    pyperclip.copy(text)
    time.sleep(0.05)  # small delay to ensure clipboard is set
    _keyboard.press(Key.cmd)
    _keyboard.press("v")
    _keyboard.release("v")
    _keyboard.release(Key.cmd)
