# Robin Local Transcription Plan

## Goal

Add an optional local transcription backend for Robin that runs on Apple Silicon, avoids cloud transcription, and can support low-latency or streaming-feeling dictation with VAD and chunk reconciliation.

This plan is intentionally research/design only. It does not replace the current Cohere backend yet.

## Summary

Running NVIDIA Parakeet locally on a Mac is possible, but the best practical path is not NVIDIA NeMo directly. NeMo's official streaming path is CUDA/PyTorch/Linux oriented. On Apple Silicon, the strongest path is:

- `mlx-audio` for the high-level MLX speech-to-text implementation.
- `mlx-community/parakeet-tdt-0.6b-v3` for local Parakeet v3 weights.
- `mlx-community/silero-vad-v6` or `mlx-community/silero-vad` for VAD.
- A local Python sidecar first, called by the Swift menu-bar app.
- Later, consider native Swift MLX only after the behavior is proven.

The desired behavior is feasible:

- Capture microphone audio continuously while the hotkey is held.
- Use VAD to detect speech boundaries and avoid sending silence into Parakeet.
- Keep short pre-roll so speech starts are not clipped.
- Decode utterances or rolling chunks with overlap.
- Merge/reconcile overlapping decoded tokens so text does not lose cohesion across chunk boundaries.
- Insert final text into the focused field using Robin's existing insertion path.

## Source Findings

### NVIDIA Parakeet v3

Source: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3

NVIDIA's `parakeet-tdt-0.6b-v3` model is:

- FastConformer-TDT.
- 600M parameters.
- Multilingual across 25 European languages.
- Uses 16 kHz mono audio.
- Supports punctuation and capitalization.
- Supports word-level and segment-level timestamps.
- Supports long audio.
- Licensed CC BY 4.0.

The model card explicitly documents a "Streaming with Parakeet models" path using NeMo:

```bash
python NeMo/main/examples/asr/asr_chunked_inference/rnnt/speech_to_text_streaming_infer_rnnt.py \
    pretrained_name="nvidia/parakeet-tdt-0.6b-v3" \
    model_path=null \
    audio_dir="<optional path to folder of audio files>" \
    dataset_manifest="<optional path to manifest>" \
    output_filename="<optional output filename>" \
    right_context_secs=2.0 \
    chunk_secs=2 \
    left_context_secs=10.0 \
    batch_size=32 \
    clean_groundtruth_text=False
```

Important implication: NVIDIA's own streaming path is not naive slicing. It uses left context, chunk context, right context, and RNNT/TDT decoding state.

### NVIDIA NeMo Streaming Path

Source: https://github.com/NVIDIA/NeMo/blob/main/examples/asr/asr_chunked_inference/rnnt/speech_to_text_streaming_infer_rnnt.py

The NeMo streaming RNNT script explains:

- Buffered inference is used for long audio.
- Streaming inference uses small chunk sizes plus right context.
- Theoretical latency is roughly `chunk size + right context`.
- Larger left context can improve transcription quality without increasing theoretical latency.
- Recommended long-file settings are around `10s left / 10s chunk / 5s right`.
- Recommended streaming settings include `10s left / 2s chunk / 2s right`, around 4 seconds theoretical latency.

The script also carries decoder state while processing chunks. That is the cohesion-preserving part of the official approach.

Practical issue: NeMo is a heavy PyTorch stack, primarily designed for NVIDIA GPUs and Linux. The script has an `allow_mps` option, but NVIDIA's Parakeet model card lists NVIDIA GPU families and Linux as the preferred/supported runtime environment. For Robin on an M1 Mac, NeMo should be treated as a reference implementation, not the first production dependency.

### MLX and MLX-Audio

Sources:

- https://github.com/Blaizzy/mlx-audio
- https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3
- https://github.com/ml-explore/mlx-swift

`mlx-audio` is currently the best practical Apple Silicon audio stack found:

- Popular: roughly 7k GitHub stars at research time.
- Maintained: recent commits in May 2026.
- Built for Apple's MLX framework.
- Supports STT, TTS, VAD, and related speech tasks.
- Supports Parakeet v2 and v3.
- Has Python APIs and CLI.
- Has an OpenAI-compatible API server and WebSocket/realtime endpoints.
- Has a Swift-related ecosystem, though the Python implementation appears more mature for STT today.

`mlx-community/parakeet-tdt-0.6b-v3` is the relevant model for Robin if we want multilingual Parakeet v3 locally. It is a large local model, around 2.5 GB.

`ml-explore/mlx-swift` is official Apple/MLX Swift infrastructure:

- Popular: roughly 1.8k GitHub stars at research time.
- Maintained: recent commits in May 2026.
- Good long-term direction for native Swift.
- But it is a lower-level MLX binding. It does not, by itself, provide a complete Parakeet transcription stack.

Recommendation: start with `mlx-audio` as a sidecar. Do not port the full Parakeet stack into Swift first.

### MLX-Audio Parakeet Streaming

Source files checked:

- `Blaizzy/mlx-audio/docs/models/stt/parakeet.md`
- `Blaizzy/mlx-audio/docs/guides/streaming.md`
- `Blaizzy/mlx-audio/mlx_audio/stt/models/parakeet/parakeet.py`

`mlx-audio` documents:

```python
from mlx_audio.stt.utils import load

model = load("mlx-community/parakeet-tdt-0.6b-v3")

for chunk in model.generate("long_audio.wav", stream=True):
    print(chunk.text, end="", flush=True)
```

From code inspection, Parakeet streaming in `mlx-audio` is chunk-overlap streaming:

- Default `chunk_duration`: 5.0 seconds.
- Default `overlap_duration`: 1.0 second.
- It decodes a chunk.
- It offsets token timestamps.
- It merges token streams using longest-contiguous matching.
- If that fails, it falls back to longest-common-subsequence merging.
- It emits the new text since the previous accumulated result.

This is exactly the kind of "smartness" Robin needs to avoid chunk-boundary incoherence. It is not the same as NeMo's cache-aware stateful streaming Conformer path, but it is probably sufficient for push-to-talk dictation and practical low-latency feedback.

### VAD

Sources:

- https://huggingface.co/mlx-community/silero-vad-v6
- https://github.com/snakers4/silero-vad
- `Blaizzy/mlx-audio/mlx_audio/vad/models/silero_vad/README.md`

Silero VAD is a strong fit:

- Popular: roughly 9k GitHub stars at research time.
- Maintained: recent commits in March 2026.
- Lightweight.
- MIT licensed.
- Very fast.
- Language-agnostic.
- Designed for streaming.

The MLX Silero VAD v6 model card describes:

- 16 kHz input.
- 32 ms streaming chunks.
- 512 new audio samples per call.
- 64-sample context from the previous chunk.
- LSTM state carried across calls.
- Scalar speech probability output.
- Typical threshold around `0.5`.
- Sub-millisecond per-chunk latency on Apple Silicon-class machines.

`mlx-audio` VAD docs show this streaming-style API:

```python
state = model.initial_state(sample_rate=16000)
probability, state = model.feed(chunk, state, sample_rate=16000)
```

For Robin, VAD should be used for:

- Avoiding silent audio getting decoded.
- Detecting utterance endpoints.
- Preventing Parakeet from hallucinating words during silence.
- Controlling when to finalize and insert text.

## Maintained/Popular Library Assessment

### Recommended

#### `Blaizzy/mlx-audio`

Use as the main local audio backend.

Reasons:

- Active in 2026.
- Popular.
- Supports the exact target model family.
- Supports MLX on Apple Silicon.
- Has VAD and STT in one package.
- Already implements chunk-overlap merging for Parakeet streaming.
- Faster to integrate and validate than a custom Swift MLX port.

Risk:

- Python sidecar adds packaging/runtime complexity.
- API may evolve.
- Need to pin versions.

#### `mlx-community/parakeet-tdt-0.6b-v3`

Use as the default local Parakeet model.

Reasons:

- Direct MLX conversion of NVIDIA Parakeet v3.
- Multilingual.
- Strong accuracy.
- Local inference on Apple Silicon.

Risk:

- Large model download.
- First-run setup cost.
- Need to benchmark M1 latency.

#### `mlx-community/silero-vad-v6`

Use for VAD if supported cleanly by `mlx-audio`; otherwise use `mlx-community/silero-vad`.

Reasons:

- Latest Silero line.
- Very small.
- Streaming-state design.
- Good fit for hotkey dictation endpointing.

Risk:

- `mlx-audio` docs currently mention `mlx-community/silero-vad`; v6 may require checking exact loader compatibility.

#### `ml-explore/mlx-swift`

Use later if/when moving to native Swift.

Reasons:

- Official Apple/MLX Swift binding.
- Maintained.
- Good long-term native direction.

Risk:

- Lower-level than `mlx-audio`.
- A full Parakeet implementation in Swift would be non-trivial.
- SwiftPM command-line builds may not build Metal shaders fully; Xcode/xcodebuild integration needs careful handling.

### Avoid As Primary Dependencies

#### `FluidInference/swift-parakeet-mlx`

Do not use as a production dependency.

Reason:

- Repository is archived.

Could still be useful as reference code only.

#### Small one-off Parakeet ports

Do not depend on them unless they are actively maintained and have enough adoption.

Reason:

- Robin should not rely on abandoned or fragile ML infrastructure.

## Proposed Architecture

### Phase 1: Local Python Sidecar

Keep Robin as a Swift menu-bar app. Add a local sidecar process for MLX transcription.

Swift app responsibilities:

- Capture microphone audio.
- Manage hotkey.
- Manage permissions.
- Store config/logs/history.
- Insert final text into focused app.
- Start/stop the local transcription sidecar.
- Send audio chunks or utterance WAVs to the sidecar.

Python sidecar responsibilities:

- Load MLX models once.
- Run VAD.
- Run Parakeet transcription.
- Return partial/final transcript events.
- Hide MLX/Python dependency complexity from the Swift app.

Communication options:

- Local HTTP server on `127.0.0.1`.
- WebSocket for streaming chunks and partials.
- Stdin/stdout JSONL protocol.

Recommended first prototype: local WebSocket or JSONL subprocess. JSONL subprocess is simpler to package and avoids port conflicts; WebSocket is closer to future realtime behavior.

### Phase 2: Local Backend Config

Add TOML settings like:

```toml
# Which transcription backend Robin uses.
# Options: "cohere" for cloud transcription, "local_parakeet" for local MLX transcription.
transcription_backend = "cohere"

# Local Parakeet model used when transcription_backend is "local_parakeet".
# Options: Hugging Face repo id or local model folder.
local_model = "mlx-community/parakeet-tdt-0.6b-v3"

# Local VAD model used for speech detection.
# Options: "mlx-community/silero-vad-v6" or "mlx-community/silero-vad".
vad_model = "mlx-community/silero-vad-v6"

# Whether to use VAD for endpointing.
# Options: true or false.
vad_enabled = true

# Speech probability threshold for VAD.
# Options: usually 0.3 to 0.7. Start with 0.5.
vad_threshold = 0.5

# Silence duration before Robin finalizes an utterance.
# Options: seconds. Start with 0.8.
vad_end_silence_seconds = 0.8

# Audio kept before VAD speech start to avoid clipping first syllables.
# Options: seconds. Start with 0.3.
vad_preroll_seconds = 0.3

# Chunk size for partial local transcription.
# Options: seconds. Lower is lower latency; higher is usually more accurate.
streaming_chunk_seconds = 2.0

# Overlap between local transcription chunks.
# Options: seconds. Must be lower than streaming_chunk_seconds.
streaming_overlap_seconds = 0.8

# Whether Robin should show partial transcription before final insertion.
# Options: true or false. Initial implementation can keep this false.
local_partial_results = false
```

### Phase 3: Local Utterance Mode

Before trying true realtime partials, implement local utterance mode:

1. Hotkey press starts recording.
2. Hotkey release stops recording.
3. WAV is sent to local sidecar.
4. Sidecar transcribes with Parakeet.
5. Swift app inserts final text.

This would match current Cohere behavior while proving:

- Model loading works.
- Model download/caching works.
- M1 performance is acceptable.
- Packaging is manageable.
- Accuracy is good.

### Phase 4: VAD Endpointing Mode

Add VAD while hotkey is held:

1. Record PCM at 16 kHz mono.
2. Feed 512-sample chunks into Silero VAD.
3. Maintain a ring buffer for pre-roll.
4. Start utterance buffer when VAD crosses threshold.
5. Continue until silence lasts `vad_end_silence_seconds`.
6. Transcribe finalized utterance.
7. Optionally insert immediately, or accumulate until hotkey release.

This keeps the UX simple and reduces bad silence transcriptions.

### Phase 5: Chunked Partial Mode

Add optional partials:

1. While speech is active, maintain a rolling audio buffer.
2. Every `streaming_chunk_seconds`, decode a chunk with `streaming_overlap_seconds`.
3. Merge chunk results using token timestamps or text LCS.
4. Do not insert partial text into the user's focused field by default.
5. On final VAD endpoint or hotkey release, insert only committed final text.

Important: inserting partial text into arbitrary apps is risky because corrections require selecting/replacing text. Robin should start by logging/showing partials, then only insert final text.

## Cohesion Strategy

The main risk in chunked ASR is repeated words, missing words, and punctuation resets at chunk boundaries.

Recommended strategy:

- Prefer token/timestamp merging if the model exposes it.
- Use overlap windows.
- Commit only text whose end timestamp is outside the current overlap zone.
- Keep a pending tail that can be revised by the next chunk.
- If token-level timestamps are not stable enough, use LCS-based text merging like `mlx-audio` does.

Conceptually:

```text
audio stream:
  [chunk A: 0.0 - 2.0s]
  [chunk B: 1.2 - 3.2s]
  [chunk C: 2.4 - 4.4s]

commit window:
  commit text ending before next overlap
  keep last ~0.8s mutable
```

This avoids committing text too early and then needing to edit it.

## Expected Performance Questions To Benchmark

Before implementing deeply, benchmark on the target M1:

- Model load time.
- First transcription latency.
- 5 second utterance latency.
- 15 second utterance latency.
- Memory usage.
- Whether v3 is fast enough or v2 is better for English-only.
- Whether quantized models are acceptable.
- Whether VAD endpointing adds negligible overhead.

Benchmark matrix:

| Model | Mode | Audio Length | Metric |
| --- | --- | --- | --- |
| Parakeet v3 | full utterance | 5s | wall time |
| Parakeet v3 | full utterance | 15s | wall time |
| Parakeet v3 | chunked | 2s chunk / 0.8s overlap | latency |
| Parakeet v2 | full utterance | 5s | wall time + quality |
| Silero VAD v6 | streaming | 32ms chunks | per-chunk latency |

## Recommended Initial Implementation Choice

Do not replace Cohere immediately. Add `local_parakeet` as an optional backend.

The safest first cut:

- Python sidecar.
- `mlx-audio`.
- Full-utterance transcription after hotkey release.
- No partial insertion.
- Detailed logs.
- TOML backend selection.

Then iterate toward:

- VAD endpointing.
- Streaming partials.
- Optional local-only mode.
- Native Swift MLX if the Python sidecar becomes too heavy.

## Risks

### Packaging

Bundling Python, MLX, model download/cache behavior, and ffmpeg/audio dependencies in a `.app` can get messy.

Mitigation:

- Start with developer-mode local dependency install.
- Use `uv` for sidecar environment management.
- Later package a self-contained Python environment or switch to Swift MLX.

### Latency

Parakeet v3 is accurate but 600M parameters. M1 may be acceptable for push-to-talk, but true low-latency partials need measurement.

Mitigation:

- Benchmark before committing to UX.
- Allow v2/v3 selection.
- Consider quantized models if available.

### Stream Quality

Chunked streaming can repeat or drop words at boundaries.

Mitigation:

- Use overlap.
- Use timestamps.
- Keep mutable tail.
- Insert only final text initially.

### Dependency Stability

`mlx-audio` is active but fast-moving.

Mitigation:

- Pin versions.
- Keep sidecar protocol small.
- Log model/library versions at startup.

## Source Links

- NVIDIA Parakeet v3: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- NVIDIA NeMo ASR models: https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/models.html
- NeMo streaming RNNT script: https://github.com/NVIDIA/NeMo/blob/main/examples/asr/asr_chunked_inference/rnnt/speech_to_text_streaming_infer_rnnt.py
- MLX-Audio: https://github.com/Blaizzy/mlx-audio
- MLX Parakeet v3: https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3
- MLX Swift: https://github.com/ml-explore/mlx-swift
- Silero VAD MLX v6: https://huggingface.co/mlx-community/silero-vad-v6
- Silero VAD upstream: https://github.com/snakers4/silero-vad
