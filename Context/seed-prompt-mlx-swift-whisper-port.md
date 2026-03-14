# Seed Prompt: Port Apple's mlx-whisper to Swift using mlx-swift

## Mission

Port Apple's official Python `mlx-whisper` implementation (3,339 lines across 8 key files) to Swift using Apple's `mlx-swift` bindings. This is a **line-by-line faithful translation**, not a reimplementation. The Python code is the source of truth — every optimization, threshold, fallback, and edge case must be preserved.

## Why This Matters

We benchmarked the existing community Swift MLX port (DePasqualeOrg/mlx-swift-audio) against Apple's Python mlx-whisper:
- **Python**: 0.319s warm avg, zero hallucinations, 2.2MB app
- **Community Swift**: 1.582s warm avg, hallucinations on silence, 98MB app

The 5x performance gap is NOT in the MLX GPU compute (same C++ engine). It's in the **orchestration layer**: decoding loop, KV cache management, logit filters, temperature fallback, hallucination detection. The community port reimplemented these differently rather than translating Apple's optimized code.

A faithful port should match Python's 0.3s performance since the underlying `mx.matmul`, `mx.softmax`, etc. map 1:1 between Python and Swift.

## Source Code Location

Apple's mlx-whisper Python source (already on disk):
```
.venv/lib/python3.13/site-packages/mlx_whisper/
├── whisper.py      (266 lines) — Model architecture: Whisper, AudioEncoder, TextDecoder, MultiHeadAttention
├── decoding.py     (741 lines) — Inference, KV cache, logit filters, GreedyDecoder, DecodingTask
├── transcribe.py   (543 lines) — Seek-based transcription loop, temperature fallback, hallucination detection
├── audio.py        (173 lines) — Mel spectrogram, STFT, pad/trim
├── tokenizer.py    (398 lines) — Whisper tokenizer wrapping tiktoken
├── timing.py       (329 lines) — DTW word-level timestamps, cross-attention alignment
├── load_models.py  ( 46 lines) — HuggingFace model download and weight loading
└── torch_whisper.py(308 lines) — Weight conversion from PyTorch format
```

## Target Architecture

Create a new Swift package or directory within `native/MuesliNative/Sources/MuesliNativeApp/` containing the ported code. The final API should be:

```swift
// Usage from TranscriptionCoordinator
let whisper = try await MLXWhisper.load(model: "mlx-community/whisper-small.en-mlx")
let result = whisper.transcribe(audioURL: url) // returns text + segments
await whisper.unload()
```

## Python → Swift API Mapping

### Core MLX operations (1:1 mapping)
| Python (`mlx.core`) | Swift (`MLX`) |
|---|---|
| `mx.array(data)` | `MLXArray(data)` |
| `mx.matmul(a, b)` | `MLX.matMul(a, b)` or `a.matmul(b)` |
| `mx.softmax(x, axis=-1)` | `MLX.softmax(x, axis: -1)` |
| `mx.argmax(x, axis=-1)` | `MLX.argMax(x, axis: -1)` |
| `mx.where(cond, a, b)` | `MLX.where(cond, a, b)` |
| `mx.concatenate([a,b])` | `MLX.concatenated([a,b])` |
| `mx.zeros(shape)` | `MLXArray.zeros(shape)` |
| `mx.ones(shape)` | `MLXArray.ones(shape)` |
| `mx.exp(x)` | `MLX.exp(x)` |
| `mx.log(x)` | `MLX.log(x)` |
| `mx.eval(x)` | `eval(x)` |
| `x.astype(mx.float16)` | `x.asType(.float16)` |
| `x.shape` | `x.shape` |
| `x[0, -1]` | `x[0, -1]` |
| `x[:, :n]` | `x[0..., ..<n]` |
| `x.reshape(shape)` | `x.reshaped(shape)` |
| `x.transpose(0, 2, 1)` | `x.transposed(0, 2, 1)` |

### Neural network layers (`mlx.nn` → `MLXNN`)
| Python | Swift |
|---|---|
| `nn.Linear(in, out)` | `Linear(in, out)` |
| `nn.Conv1d(...)` | `Conv1d(...)` |
| `nn.LayerNorm(n)` | `LayerNorm(dimensions: n)` |
| `nn.Embedding(n, d)` | `Embedding(embeddingCount: n, dimensions: d)` |
| `nn.GELU()` | `GELU()` |
| `nn.Module` | `Module` |

### Utility
| Python | Swift |
|---|---|
| `tree_map(fn, tree)` | Manual recursion on nested tuples/arrays |
| `np.frombuffer(...)` | `Data` / `UnsafeBufferPointer` |
| `zlib.compress(...)` | `NSData compressed with .zlib` |
| `base64.decodebytes(...)` | `Data(base64Encoded:)` |
| `tiktoken` | `SwiftTiktoken` package (already patched, at `LocalPackages/swift-tiktoken/`) |

## Files to Port (in order)

### 1. `whisper.py` → `WhisperModel.swift` (266 lines)

The model architecture. Port these classes:
- `ModelDimensions` dataclass → Swift struct
- `sinusoids()` → positional embeddings function
- `MultiHeadAttention` → Multi-head attention with KV cache support
- `ResidualAttentionBlock` → Attention + MLP block with KV cache passthrough
- `AudioEncoder` → Conv1d + positional embedding + transformer blocks
- `TextDecoder` → Token embedding + positional embedding + transformer blocks + KV cache
- `Whisper` → Top-level model combining encoder + decoder

**Critical**: The KV cache is a list of tuples `[(K, V)]` per layer. The `TextDecoder.__call__` method accepts and returns `kv_cache`. This must be preserved exactly — it's the #1 performance differentiator.

```python
# Python KV cache structure:
# kv_cache = [(k1, v1), (k2, v2), ...] per self-attention layer
# cross_kv_cache = [(k1, v1), (k2, v2), ...] per cross-attention layer
# After first pass, only new token positions are computed (incremental decoding)
```

### 2. `audio.py` → `WhisperAudio.swift` (173 lines)

Audio preprocessing. Port:
- `SAMPLE_RATE = 16000`, `N_FFT = 400`, `HOP_LENGTH = 160`, `CHUNK_LENGTH = 30`, `N_FRAMES = 3000`
- `log_mel_spectrogram()` — STFT → mel filterbank → log scale. Use `MLXFFT` for the FFT.
- `pad_or_trim()` — Pad/trim audio to 30 seconds
- Mel filterbank weights (need to be loaded or computed)

**Note**: The mel filterbank matrix is 80×201 (or 128×201 for large-v3). In Python it's loaded from a NumPy `.npz` file bundled with the package. You'll need to either bundle this as a resource or compute it from the formula.

### 3. `tokenizer.py` → `WhisperTokenizer.swift` (398 lines)

Tokenizer wrapping tiktoken. Port:
- `get_tokenizer()` factory
- `Tokenizer` class with special tokens: `sot`, `eot`, `transcribe`, `translate`, `no_timestamps`, `timestamp_begin`
- Language token mapping
- `decode()` and `encode()` methods
- Uses `tiktoken` — map to `SwiftTiktoken` package

### 4. `decoding.py` → `WhisperDecoding.swift` (741 lines)

**THE MOST CRITICAL FILE.** This is where the community port diverged. Port faithfully:

- `compression_ratio()` — zlib compression ratio for hallucination detection
- `Inference` class — wraps model forward pass, manages KV cache, `rearrange_kv_cache` for beam search
- `GreedyDecoder` — temperature=0 greedy token selection with sum_logprobs tracking
- `LogitFilter` protocol and implementations:
  - `SuppressBlank` — suppress blank at beginning
  - `SuppressTokens` — suppress specific token IDs
  - `ApplyTimestampRules` — enforce timestamp monotonicity
- `DecodingTask` — the main decode loop:
  - `_get_initial_tokens()` — builds SOT + language + task tokens
  - `_get_suppress_tokens()` — builds suppress list
  - `_main_loop()` — token-by-token generation with logit filtering
  - Handles KV cache for incremental decoding
  - Temperature fallback: `[0.0, 0.2, 0.4, 0.6, 0.8, 1.0]`
  - Compression ratio check, avg logprob check, no-speech prob check

**Key performance detail**: The `Inference.logits()` method passes KV cache to the decoder and gets updated cache back. On subsequent tokens, only the new token's KV is computed (not the full sequence). This is what makes it fast. If you recompute the full sequence each token, it's 100x slower.

### 5. `transcribe.py` → `WhisperTranscribe.swift` (543 lines)

The seek-based transcription loop. Port:
- `transcribe()` — main entry point
- Seek pointer advances through 30-second mel segments
- `decode_with_fallback()` — tries increasing temperatures
- Consecutive timestamp detection for segment splitting
- Single timestamp ending handling
- No-speech detection (skip silent segments)
- Hallucination filtering (compression ratio + logprob thresholds)
- `new_segment()` — creates segment dict from decode result
- Word timestamp integration (calls `timing.add_word_timestamps`)

### 6. `timing.py` → `WhisperTiming.swift` (329 lines)

Word-level timestamps via DTW alignment:
- `dtw()` — Dynamic Time Warping
- `find_alignment()` — cross-attention weight extraction + DTW
- `add_word_timestamps()` — splits segments into words with timestamps
- `median_filter()` — smooths attention weights
- Word anomaly detection for hallucination filtering

### 7. `load_models.py` → `WhisperModelLoader.swift` (46 lines)

Model weight loading from HuggingFace. Use Swift `Hub` library or simple URLSession download + `MLX.loadArrays()` for safetensors/npz.

## Dependencies for the Swift Port

```swift
// Package.swift dependencies needed:
.package(url: "https://github.com/ml-explore/mlx-swift", branch: "main"),  // MLX, MLXNN, MLXFFT
.package(path: "LocalPackages/swift-tiktoken"),  // Already patched for Swift 5.9
```

Products to import: `MLX`, `MLXNN`, `MLXFFT`, `MLXRandom`, `SwiftTiktoken`

**Do NOT use** `mlx-swift-audio` or `mlx-swift-lm` — those are the community packages. This port uses Apple's `mlx-swift` directly.

## What NOT to Do

1. **Do NOT reimagine the architecture.** The community port (DePasqualeOrg) added Observable conformance, MainActor isolation, different class hierarchies. This added overhead and broke the decoding pipeline. Translate 1:1.

2. **Do NOT add beam search.** Apple's mlx-whisper only implements greedy decoding (temperature=0) and sampling (temperature>0). Beam search is defined but never used by default. Skip it.

3. **Do NOT add async/await to the model forward pass.** The Python code is synchronous. MLX operations are lazy-evaluated and batched by `mx.eval()`. Adding async boundaries between MLX ops breaks the computation graph optimization.

4. **Do NOT use `@MainActor` on the model or decoder.** The community port did this and it serialized GPU operations onto the main thread. The model should be `nonisolated` — MLX handles thread safety internally.

5. **Do NOT import `MLXLMCommon`, `MLXLLM`, or `HuggingFace Hub`.** Those bring in 50MB+ of unnecessary dependencies. Load weights directly with `MLX.loadArrays(url:)`.

## Testing & Validation

1. **Benchmark**: Compare against Python mlx-whisper using `benchmarks/bench_mlx.py` and a Swift equivalent. Target: within 10% of Python's 0.319s warm avg on whisper-small.en.

2. **Accuracy**: Transcribe the same test audio (`/tmp/muesli-test-audio/LJ037-0171.wav`) with both Python and Swift. Output must be identical: "The examination and testimony of the experts enabled the Commission to conclude that five shots may have been fired."

3. **Hallucination test**: Feed a silent WAV. Python returns empty/near-empty text. Swift must match — no `[BLANK_AUDIO]`, no repetitions.

4. **KV cache verification**: Second transcription with warm model should be as fast as first warm run. If it's slower, KV cache is being rebuilt instead of reused.

## Build Requirements

- Swift 6.1.2 (Xcode 16.4)
- macOS 15.5
- `mlx-swift` requires macOS 15+ for `Synchronization`/`Atomic` module
- Metal GPU required (use `xcodebuild` not `swift build` — `swift build` doesn't compile Metal shaders)

## Current Muesli Integration Point

The ported code should expose a simple API that `TranscriptionCoordinator` in `native/MuesliNative/Sources/MuesliNativeApp/TranscriptionRuntime.swift` can call. Currently it calls `PythonWorkerClient.transcribeFileAsync()`. The Swift port would replace that with a direct function call — no subprocess, no IPC, no Python.

## Reference: Why the Community Port Was Slow

Specific issues found in DePasqualeOrg/mlx-swift-audio's `WhisperDecoding.swift` (447 lines vs Apple's 741):
- Missing `LogitFilter` protocol — no `SuppressBlank`, `SuppressTokens`, `ApplyTimestampRules`
- Simplified KV cache — didn't preserve incremental decoding properly
- No temperature fallback sequence — used fixed temperature
- Missing compression ratio check — allowed hallucinated repetitive output
- `@MainActor` on `WhisperEngine` — serialized GPU ops to main thread
- `eval(logits)` called after every token — should batch evals
- Missing `rearrange_kv_cache` for cache management

Every one of these exists in Apple's Python code and must be in the Swift port.
