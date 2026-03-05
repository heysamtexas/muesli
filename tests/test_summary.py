import json
from unittest.mock import patch, MagicMock
from meeting.summary import summarize_transcript


class TestSummarizeTranscript:
    @patch.dict("os.environ", {}, clear=True)
    def test_no_api_key_returns_raw_transcript(self):
        # No API key set, no config file
        with patch("os.path.exists", return_value=False):
            result = summarize_transcript("You: hello\nOthers: hi", "Test Meeting")
        assert "Raw Transcript" in result
        assert "You: hello" in result
        assert "Test Meeting" in result

    @patch("meeting.summary.urllib.request.urlopen")
    @patch.dict("os.environ", {"OPENROUTER_API_KEY": "test-key"})
    def test_api_call_returns_formatted_notes(self, mock_urlopen):
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "choices": [{"message": {"content": "## Summary\nGood meeting."}}]
        }).encode()
        mock_response.__enter__ = lambda s: mock_response
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        result = summarize_transcript("You: hello", "My Meeting")
        assert "My Meeting" in result
        assert "Good meeting" in result
        mock_urlopen.assert_called_once()

    @patch("meeting.summary.urllib.request.urlopen")
    @patch.dict("os.environ", {"OPENROUTER_API_KEY": "test-key"})
    def test_api_error_falls_back_to_raw(self, mock_urlopen):
        mock_urlopen.side_effect = Exception("Network error")
        result = summarize_transcript("You: hello", "Failed Meeting")
        assert "Raw Transcript" in result
        assert "You: hello" in result
