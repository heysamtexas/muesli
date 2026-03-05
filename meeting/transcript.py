from datetime import datetime, timedelta


def merge_transcripts(
    mic_segments: list[dict],
    system_segments: list[dict],
    meeting_start: datetime,
) -> str:
    """Merge mic (You) and system (Others) transcript segments chronologically.

    Each segment is {"start": float, "end": float, "text": str} where start/end
    are seconds from the beginning of the recording.

    Returns a formatted transcript string.
    """
    # Tag each segment with speaker
    tagged = []
    for seg in mic_segments:
        tagged.append({**seg, "speaker": "You"})
    for seg in system_segments:
        tagged.append({**seg, "speaker": "Others"})

    # Sort by start time
    tagged.sort(key=lambda s: s["start"])

    # Format
    lines = []
    for seg in tagged:
        timestamp = meeting_start + timedelta(seconds=seg["start"])
        time_str = timestamp.strftime("%H:%M:%S")
        lines.append(f"[{time_str}] {seg['speaker']}: {seg['text']}")

    return "\n".join(lines)


def format_raw_transcript(segments: list[dict], speaker: str, meeting_start: datetime) -> str:
    """Format segments from a single speaker."""
    lines = []
    for seg in segments:
        timestamp = meeting_start + timedelta(seconds=seg["start"])
        time_str = timestamp.strftime("%H:%M:%S")
        lines.append(f"[{time_str}] {speaker}: {seg['text']}")
    return "\n".join(lines)
