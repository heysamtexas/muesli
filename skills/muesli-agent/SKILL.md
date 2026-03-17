---
name: muesli-agent
description: Use when working with local Muesli meetings, notes, dictations, or raw transcripts through the bundled `muesli-cli` CLI. Prefer this skill when a coding agent needs to inspect transcripts, summarize meetings with its own model, or write notes back into Muesli without requiring the user's API keys.
---

# Muesli Agent

Use the local `muesli-cli` CLI as the source of truth for meeting and dictation data.

## CLI discovery

Resolve the binary in this order:
1. `command -v muesli-cli`
2. `/Applications/Muesli.app/Contents/MacOS/muesli-cli`
3. A local SwiftPM build path inside this repo

If discovery is uncertain, run `muesli-cli info` first.

## Core workflow

1. Inspect capabilities with `muesli-cli spec` if you do not know the exact subcommand shape.
2. List candidate meetings with `muesli-cli meetings list --limit 10`.
3. Fetch a full record with `muesli-cli meetings get <id>`.
4. Use the coding agent's own model to analyze `rawTranscript` and `formattedNotes`.
5. If you want to persist improved notes, write markdown back with:
   - `cat notes.md | muesli-cli meetings update-notes <id> --stdin`
   - or `muesli-cli meetings update-notes <id> --file notes.md`

## Rules

- Treat CLI stdout as the machine-readable API. It is JSON by default.
- Treat stderr as informational only.
- Do not mutate `rawTranscript`; only update `formattedNotes`.
- Prefer the meeting transcript when `notesState` is `missing` or `raw_transcript_fallback`.
- Use `--db-path` or `--support-dir` only when the default Muesli data location is wrong.

## When to read references

Read `references/cli-contract.md` if you need the exact command tree, field definitions, or failure behavior.
