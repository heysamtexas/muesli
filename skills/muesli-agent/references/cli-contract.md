# Muesli CLI Contract

## Commands

- `muesli-cli spec`
- `muesli-cli info`
- `muesli-cli meetings list [--limit N] [--folder-id ID]`
- `muesli-cli meetings get <id>`
- `muesli-cli meetings update-notes <id> (--stdin | --file <path>)`
- `muesli-cli dictations list [--limit N]`
- `muesli-cli dictations get <id>`

## Output shape

All commands return JSON to stdout.

Success envelope:
```json
{
  "ok": true,
  "command": "muesli-cli meetings get",
  "data": {},
  "meta": {
    "schemaVersion": 1,
    "generatedAt": "2026-03-17T00:00:00Z",
    "dbPath": "/Users/example/Library/Application Support/Muesli/muesli.db",
    "warnings": []
  }
}
```

Failure envelope:
```json
{
  "ok": false,
  "command": "muesli-cli meetings get 999",
  "error": {
    "code": "not_found",
    "message": "No meeting exists with id 999.",
    "fix": "Run `muesli-cli meetings list` to find a valid ID."
  },
  "meta": {
    "schemaVersion": 1,
    "generatedAt": "2026-03-17T00:00:00Z",
    "dbPath": "",
    "warnings": []
  }
}
```

## Important fields

Meeting list rows include:
- `id`
- `title`
- `startTime`
- `durationSeconds`
- `wordCount`
- `folderID`
- `notesState`

Meeting details also include:
- `rawTranscript`
- `formattedNotes`
- `calendarEventID`
- `micAudioPath`
- `systemAudioPath`

`notesState` values:
- `missing`
- `raw_transcript_fallback`
- `structured_notes`

Dictation details include:
- `rawText`
- `appContext`
- `timestamp`
- `durationSeconds`

## Expected agent pattern

- `list` to discover IDs
- `get` to fetch full text
- external summarize/analyze in the coding agent
- `update-notes` to write notes back
