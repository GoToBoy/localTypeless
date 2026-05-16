# local-typeless

Native macOS menu-bar dictation app for fully local dictation. Press a global
hotkey, speak, let WhisperKit transcribe English or Chinese, optionally polish
the transcript with an on-device MLX LLM, and paste the final text back into the
app that had focus when recording started.

After the initial model downloads, dictation runs offline. There are no network
calls in the recording, transcription, polish, paste, or history path.

## Features

- Global hotkey with toggle and push-to-talk modes. The default is double-tap
  right Option.
- Floating recording HUD with live audio-level feedback plus cancel and finish
  controls while recording.
- Local ASR via WhisperKit using Whisper Large v3 Turbo.
- Optional local polish via MLX using Qwen2.5-3B-Instruct-4bit, with automatic,
  on, and off modes.
- Memory-aware model lifecycle: downloaded models load on demand, resident
  models can be unloaded, and polish is skipped gracefully when memory is tight.
- English, Chinese, and auto ASR language modes, with final text normalization
  for CJK spacing.
- Paste injection through CGEvent or AppleScript. If automatic paste is blocked,
  the text stays on the clipboard and the app offers a clear fallback.
- Full pasteboard preservation when enabled, including non-string clipboard
  items.
- Local searchable history via SQLite, plus optional raw-audio retention with
  rolling cleanup.
- First-run onboarding for Microphone, Accessibility, and Input Monitoring
  permissions.
- Localized UI in English and Simplified Chinese.

## Build flavors

Two builds, two project specs, both 100% local — no audio or text ever leaves the device.

| Flavor | Spec | ASR | Polish | Target hardware |
|---|---|---|---|---|
| **Apple Silicon** (default) | [project.yml](project.yml) | WhisperKit (Core ML + ANE) | MLX (Qwen 2.5 3B 4-bit) | M-series Macs |
| **Portable** | [project.portable.yml](project.portable.yml) | whisper.cpp via [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) (`ggml-small`, ~470 MB) | none | Intel Mac, experimental only |

Both inherit shared settings from [project.base.yml](project.base.yml). Engine selection is compile-time via the `APPLE_SILICON_ENGINE` flag — see [EngineFactory.swift](LocalTypeless/Services/Engines/EngineFactory.swift).

### Intel / Portable status

The portable Intel build is experimental and is not considered production-ready
for normal dictation. It can record microphone audio, but ASR runs through
whisper.cpp on CPU instead of WhisperKit/Core ML/ANE. On the current benchmark
fixtures, the default `ggml-small` model took about 31-32 seconds to transcribe
2.3-2.5 seconds of English or Chinese audio, which is too slow for hotkey
dictation.

Smaller whisper.cpp models improve latency but still carry tradeoffs: `base`
was around 14 seconds on the same fixtures, while `tiny` was around 9 seconds
with higher accuracy risk. Treat Intel artifacts as compatibility experiments,
not as the recommended user build. The supported path is Apple Silicon.

## Build

```sh
make bootstrap-signing # create the stable local signing identity once
make generate          # regenerate LocalTypeless.xcodeproj from project.yml
make build             # build the Apple Silicon flavor (.app at build/arm64/...)
make test              # Apple Silicon + run unit tests
make run               # launch the debug build (arm64)
make install           # install, sign, and open /Applications/LocalTypeless.app

# Portable / Intel x86_64 flavor — no MLX, no LLM polish; whisper.cpp ASR only
make build-portable    # .app at build/x86_64/...
make test-portable     # portable unit tests

make clean             # remove build artifacts and generated project files
```

The Xcode projects are generated from `project.yml` / `project.portable.yml`
with XcodeGen. Do not edit either `*.xcodeproj/` by hand.

## Requirements

- macOS 14+
- Xcode 15.3+ (Swift 5.9)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A stable local code-signing identity for installed builds. Run
  `make bootstrap-signing`, then use `make install`.
- Permissions for Microphone, Accessibility, and Input Monitoring.
- Disk space for local models: about 1.5 GB for ASR and about 2 GB for polish.
- 16 GB RAM is recommended for automatic polish. The speech model is required;
  the polish model is optional and can be disabled.

## First Run

1. Install with `make install` for stable local signing.
2. Grant Microphone, Accessibility, and Input Monitoring permissions in the
   onboarding flow.
3. Download the speech model when prompted. The polish model can be downloaded
   later from Settings.
4. Press the hotkey, speak, and stop recording. The app transcribes, optionally
   polishes, then pastes into the original target app.

If Accessibility permission is missing or the target app cannot be focused, the
dictation text remains on the clipboard so it can be pasted manually.

## Models

| Model | Purpose | Approx. disk | Runtime behavior |
| --- | --- | ---: | --- |
| Whisper Large v3 Turbo | Speech-to-text | 1.5 GB | Mandatory, loads on demand |
| Qwen2.5-3B-Instruct-4bit | Transcript polish | 2 GB | Optional, memory-aware |

Downloaded means the files are on disk. Ready in memory means the model is
resident and immediately available for inference.

## Data

Local app data lives under:

```text
~/Library/Application Support/local-typeless/
```

History is stored in `history.sqlite`. Optional retained audio is stored as WAV
files under `audio/` and pruned according to the retention setting. Model caches
are local Application Support directories managed by WhisperKit and MLX.

## Docs

- [AGENTS.md](AGENTS.md) - canonical entry (stack, layout, dev commands, conventions)
- [docs/](docs/index.md) - progressive spec: architecture, operations, references, product
- [Pipeline](docs/architecture/pipeline.md)
- [Models](docs/architecture/models.md)
- [Hotkeys](docs/architecture/hotkeys.md)
- [Operations](docs/operations/index.md)
