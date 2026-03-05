from datetime import datetime
from meeting.transcript import merge_transcripts, format_raw_transcript


class TestMergeTranscripts:
    def test_empty_inputs(self):
        result = merge_transcripts([], [], datetime(2026, 3, 5, 10, 0, 0))
        assert result == ""

    def test_mic_only(self):
        mic = [{"start": 0.0, "end": 5.0, "text": "Hello from mic"}]
        result = merge_transcripts(mic, [], datetime(2026, 3, 5, 10, 0, 0))
        assert "You: Hello from mic" in result
        assert "10:00:00" in result

    def test_system_only(self):
        system = [{"start": 0.0, "end": 5.0, "text": "Hello from speaker"}]
        result = merge_transcripts([], system, datetime(2026, 3, 5, 10, 0, 0))
        assert "Others: Hello from speaker" in result

    def test_interleaved_by_timestamp(self):
        mic = [
            {"start": 0.0, "end": 5.0, "text": "I said this first"},
            {"start": 10.0, "end": 15.0, "text": "Then I replied"},
        ]
        system = [
            {"start": 5.0, "end": 10.0, "text": "They said this second"},
        ]
        result = merge_transcripts(mic, system, datetime(2026, 3, 5, 10, 0, 0))
        lines = result.strip().split("\n")
        assert len(lines) == 3
        assert "You: I said this first" in lines[0]
        assert "Others: They said this second" in lines[1]
        assert "You: Then I replied" in lines[2]

    def test_timestamps_offset_correctly(self):
        mic = [{"start": 65.0, "end": 70.0, "text": "One minute in"}]
        result = merge_transcripts(mic, [], datetime(2026, 3, 5, 10, 0, 0))
        assert "10:01:05" in result

    def test_format_raw_transcript(self):
        segments = [
            {"start": 0.0, "end": 5.0, "text": "First"},
            {"start": 30.0, "end": 35.0, "text": "Second"},
        ]
        result = format_raw_transcript(segments, "You", datetime(2026, 3, 5, 14, 30, 0))
        assert "14:30:00" in result
        assert "14:30:30" in result
        assert "You: First" in result
        assert "You: Second" in result
