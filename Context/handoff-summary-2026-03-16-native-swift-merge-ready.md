# Context Handover — Native Swift branch ready to merge: FluidAudio + whisper.cpp, zero Python

**Session Date:** 2026-03-16
**Repository:** muesli
**Branch:** `native-swift` (ready to merge into `main`)

---

## Session Objective
Replace the 658MB Python runtime with native Swift transcription backends, validate FluidAudio Parakeet on ANE, add whisper.cpp for Whisper models, implement custom Nemotron RNNT backend, port all post-processing to Swift, and build a Models management UI.

## What Got Done

### Native ASR Backends (32MB app, zero Python)
- **FluidAudio** (Parakeet TDT v2/v3): 0.09-0.13s on ANE. Production default.
- **SwiftWhisper** (whisper.cpp): Whisper Small/Medium/Large Turbo on Metal/CPU. ~1.2s.
- **Nemotron RNNT** (custom CoreML): Written from scratch (~280 lines). Downloads and loads but RNNT decode produces empty transcripts. Excluded from model list, tracked in GitHub issue #1.

### Models Eliminated
- **Qwen3 ASR CoreML**: Tested, 64.5s per transcription — autoregressive decoder too slow on CoreML. Removed.
- **Qwen3 ASR via speech-swift**: Rejected — downloads closed-source `SpeechCore.xcframework`. Discovered FluidAudio already has `Qwen3AsrManager` built in.

### Post-Processing Pipeline (fully native Swift)
- **Filler word removal**: Strips uh, um, er, hmm, "you know," "i mean," etc. Deterministic, zero latency.
- **Custom word matching**: Jaro-Winkler similarity (>0.85 threshold) ported from Python's jellyfish. Fixed crash on short strings (1 char vs long word).
- **Pre-loaded dictionary**: "muesli" in default custom words so Parakeet's "musley"/"museli" gets corrected.

### Silero VAD (meeting pipeline)
- FluidAudio's `VadManager` (Silero v5 CoreML) runs on each 30s meeting chunk before transcription.
- Silent chunks skipped — prevents Whisper hallucinations.

### Models Management UI
- **Models sidebar tab**: Download/delete/set-active per model with progress bars and status badges.
- **Coming Soon section**: Qwen3 ASR and Nemotron Streaming shown greyed out with "Experimental" badge.
- **Recommended badge**: Parakeet v3 marked as recommended in onboarding and Models tab.
- **Background downloads**: Onboarding advances immediately while model downloads in background.
- **Minimum progress visibility**: Downloads visible for at least 1.5s even if fast.

### Onboarding Updates
- Model step shows all available models from `BackendOption.all` with Recommended badge.
- "Download & Continue" starts background download, doesn't block flow.
- Subtitle: "Pick a model to get started. You can download more from the Models tab later."

### Bug Fixes
- **Whisper Small crash**: Model filename was `ggml-small.en-q5_0.bin` (doesn't exist on HF), corrected to `q5_1`. Added file size validation (>10MB) to prevent SwiftWhisper force-unwrap crash on corrupted downloads.
- **Jaro-Winkler crash**: `start...end` range invalid when comparing 1-char words. Added `guard start <= end`.
- **Floating indicator hotkey text**: Was hardcoded "Hold Left Cmd to dictate". Now reads from `config.dictationHotkey.label` and updates dynamically.
- **DictationsView empty state**: Same hardcoded text fixed.

### Test Coverage
- **86 tests passing**: BackendTests, CustomWordMatcherTests (Jaro-Winkler edge cases), FillerWordFilterTests, ModelsTests, TranscriptionRuntimeTests, and all existing tests updated.

## Key Metrics

| Metric | main (Python) | native-swift |
|--------|--------------|-------------|
| App size | 668 MB | 32 MB |
| Dictation speed | 0.32s | 0.13s |
| Runtime deps | 658 MB Python venv | None |
| Model download | ~150 MB (Whisper Small) | ~250 MB (Parakeet v3) |
| Tests | ~40 | 86 |
| VAD | RMS energy (basic) | Silero VAD (CoreML) |
| Custom words | jellyfish (Python) | Jaro-Winkler (native) |
| Filler removal | None | Built-in |

## Files on native-swift (not in main)

### Created
- `FluidAudioBackend.swift` — Parakeet TDT transcriber (ANE)
- `WhisperCppBackend.swift` — Whisper transcriber (Metal) + model download + progress delegate
- `NemotronStreamingBackend.swift` — Custom RNNT CoreML pipeline (experimental)
- `CustomWordMatcher.swift` — Jaro-Winkler fuzzy matching for personal dictionary
- `FillerWordFilter.swift` — Deterministic filler word removal
- `ModelsView.swift` — Model management sidebar tab
- `Tests/BackendTests.swift`, `Tests/CustomWordMatcherTests.swift`, `Tests/FillerWordFilterTests.swift`

### Significantly Modified
- `Package.swift` — Added FluidAudio + SwiftWhisper dependencies
- `Models.swift` — 5 active models + 2 coming soon, sizeLabel/description/recommended fields
- `TranscriptionRuntime.swift` — Multi-backend routing, VAD, filler removal, custom words
- `MuesliController.swift` — Removed Python worker, FluidAudio-first initialization
- `RuntimePaths.swift` — Optional Python paths, native-only bundle support
- `OnboardingView.swift` — Background downloads, recommended badge, model list from BackendOption.all
- `AppState.swift` — Added `.models` tab
- `SidebarView.swift` — Models sidebar item
- `DashboardRootView.swift` — ModelsView routing
- `FloatingIndicatorController.swift` — Dynamic hotkey label
- `DictationsView.swift` — Dynamic hotkey label

### Retained but unused
- `PythonWorkerClient.swift`, `PythonWorkerClientAsync.swift` — Still compiles but not instantiated
- `bridge/worker.py`, `transcribe/backends.py` — Python side unchanged

## Merge Strategy

`native-swift` should merge into `main`. The merge will:
1. Replace Python-based transcription with native FluidAudio/whisper.cpp
2. Add Models tab, filler removal, custom word matching, Silero VAD
3. Keep all Python files in repo (bridge/, transcribe/) but they won't be used
4. Build script needs updating to skip Python runtime bundling for native builds

Post-merge cleanup:
- Remove `bridge/worker.py`, `transcribe/`, Python worker Swift files
- Update `build_native_app.sh` to skip Python runtime
- Consider keeping Python files on a `legacy-python` branch for reference

## Open Issues
- GitHub #1: Nemotron RNNT decode produces empty transcripts
- whisper.cpp via SwiftWhisper is 3-4x slower than Python mlx-whisper for Whisper models
- SwiftWhisper last updated May 2024 — consider forking or vendoring
- Download progress for FluidAudio models may not propagate to UI reliably
