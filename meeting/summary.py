import json
import os
import urllib.request

OPENROUTER_API_KEY_ENV = "OPENROUTER_API_KEY"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

# Default model — can be overridden in config. Free models on OpenRouter:
# google/gemma-3-1b-it:free, meta-llama/llama-3.2-1b-instruct:free, etc.
DEFAULT_MODEL = "google/gemma-3-4b-it:free"

SUMMARY_PROMPT = """You are a meeting notes assistant. Given a raw meeting transcript, produce structured meeting notes with the following sections:

## Meeting Summary
A 2-3 sentence overview of what was discussed.

## Key Discussion Points
- Bullet points of main topics discussed

## Decisions Made
- Bullet points of any decisions reached

## Action Items
- [ ] Bullet points of tasks assigned or agreed upon, with owners if mentioned

## Notable Quotes
- Any important or notable statements (if applicable)

Keep it concise and professional. If a section has no content, write "None noted."

Raw transcript:
"""


def summarize_transcript(
    transcript: str,
    meeting_title: str = "",
    model: str | None = None,
) -> str:
    """Send transcript to OpenRouter for structured summarization.

    Returns formatted meeting notes as a string.
    Falls back to raw transcript if API is unavailable.
    """
    api_key = os.environ.get(OPENROUTER_API_KEY_ENV, "")
    if not api_key:
        config_path = os.path.expanduser("~/Library/Application Support/Muesli/config.json")
        if os.path.exists(config_path):
            with open(config_path) as f:
                cfg = json.load(f)
            api_key = cfg.get("openrouter_api_key", "")

    if not api_key:
        print("[summary] No OpenRouter API key found. Returning raw transcript.")
        print("[summary] Set OPENROUTER_API_KEY env var or add 'openrouter_api_key' to config.json")
        return f"# {meeting_title or 'Meeting Notes'}\n\n## Raw Transcript\n\n{transcript}"

    model = model or DEFAULT_MODEL
    prompt = SUMMARY_PROMPT + transcript

    if meeting_title:
        prompt = f"Meeting title: {meeting_title}\n\n" + prompt

    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 2000,
    }).encode("utf-8")

    req = urllib.request.Request(
        OPENROUTER_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/muesli-app",
            "X-Title": "Muesli Meeting Notes",
        },
    )

    try:
        print(f"[summary] Sending to OpenRouter ({model})...")
        with urllib.request.urlopen(req, timeout=60) as resp:
            result = json.loads(resp.read())
            notes = result["choices"][0]["message"]["content"]
            print(f"[summary] Summary generated ({len(notes)} chars)")
            return f"# {meeting_title or 'Meeting Notes'}\n\n{notes}"
    except Exception as e:
        print(f"[summary] OpenRouter error: {e}")
        return f"# {meeting_title or 'Meeting Notes'}\n\n## Raw Transcript\n\n{transcript}"
