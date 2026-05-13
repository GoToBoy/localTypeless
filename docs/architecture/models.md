# Models

Two large on-device models. They are the dominant RAM consumer and the only thing that needs a network to fetch.

## Inventory

`ModelKind` enumerates every model the app uses:

| Kind | Purpose | Backend | Size on disk | RAM resident |
|------|---------|---------|--------------|--------------|
| `asrWhisperLargeV3Turbo` | Speech-to-text (EN + ZH) | WhisperKit / CoreML | ~1.5 GB | ~1.5 GB |
| `polishQwen25_3bInstruct4bit` | Fill-word removal, punctuation, rewrite | MLX Swift | ~2 GB | ~2 GB |

Budget target: ~4 GB total resident (models + buffers + app), leaving headroom on a 16 GB base-config Mac mini.

## Lifecycle

Each model has a manager conforming to `ModelLifecycle` (see `Services/Models/`):

- `WhisperKitModelManager` — implements `ASRModelManaging`.
- `MLXPolishModelManager` — implements `PolishModelManaging`.

Both publish their state through the shared `ModelStatusStore` (an `@Observable` `@MainActor` class keyed by `ModelKind`). Status transitions:

```
notDownloaded → downloading(progress) → downloaded → loading → resident
                                                   ↓
                                                failed(message)
```

- `notDownloaded` — nothing on disk.
- `downloading(progress:)` — fetch in progress; `progress ∈ 0...1`. UI shows a progress bar. ([Known v1 limitation](../product/index.md#v1-limitations) — WhisperKit only surfaces `0`/`1`, not continuous progress.)
- `downloaded` — files on disk, not in RAM.
- `loading` — opening model files into RAM.
- `resident` — ready for inference. `isReady(_:)` returns true.
- `failed(message:)` — any error, manager-specific message.

`ModelStatusStore.isReady(_:)` means the model is already resident in RAM.
`ModelStatusStore.canLoadOnDemand(_:)` means the files are available and the
dictation path may load the model automatically when it is first needed.

`MemoryAdvisor` samples total physical memory and currently available memory
before optional model work:

- ASR is required, but it is only background-prewarmed when the model is already downloaded and at least ~3 GB is currently available.
- Polish is optional. In `automatic` mode it only runs when the polish model is downloaded, total memory is at least ~16 GB, and at least ~4 GB is currently available.
- If the user explicitly turns polish `on`, the app still skips it when currently available memory is below ~3 GB, and uses the raw transcript instead.
- If polish is skipped for memory, the app warns once and continues with transcription + paste.

## Gating

`AppDelegate.ensureModelsDownloadedForRecording()` runs on every hotkey press:

- If the ASR model is not downloaded, it opens `ModelDownloadView` and returns `false` — recording never starts.
- The polish model is not a hard recording dependency in `automatic` or `off` mode. If unavailable or memory-constrained, the pipeline skips polish and injects the raw transcript.
- If required model files are already downloaded, recording starts immediately. ASR and enabled polish services call `ensureReady(_:)` later in the dictation path, so loading into RAM is automatic and on demand.
- There is no auto-download on launch. Model fetch is always explicit.

## Unload

Menu → **Unload models** calls `ModelLifecycle.unload(_:)` on each manager. Status reverts to `.downloaded` (files still on disk). Next hotkey press re-enters the `loading` → `resident` path without a download.

## On-disk locations

WhisperKit and MLX each own their download directories (HuggingFace-style caches under Application Support). The app never writes to those directly; it only consumes the managers' `isReady` signal.
