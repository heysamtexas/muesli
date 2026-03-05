from unittest.mock import patch, MagicMock, call
from pynput.keyboard import Key
from dictation.paste import paste_text


class TestPasteText:
    @patch("dictation.paste._keyboard")
    @patch("dictation.paste.pyperclip")
    def test_paste_copies_and_simulates_cmd_v(self, mock_clip, mock_kb):
        paste_text("hello world")
        mock_clip.copy.assert_called_once_with("hello world")
        mock_kb.press.assert_any_call(Key.cmd)
        mock_kb.press.assert_any_call("v")
        mock_kb.release.assert_any_call("v")
        mock_kb.release.assert_any_call(Key.cmd)

    @patch("dictation.paste._keyboard")
    @patch("dictation.paste.pyperclip")
    def test_empty_text_does_nothing(self, mock_clip, mock_kb):
        paste_text("")
        mock_clip.copy.assert_not_called()
        mock_kb.press.assert_not_called()
