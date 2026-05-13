# Dictation pipeline

The dictation flow is a single async function: [`DictationPipeline.run(_:onEvent:)`](../../LocalTypeless/Core/DictationPipeline.swift). It takes a captured audio buffer plus config and emits events. The app delegate maps those events onto a `StateMachine` so the menu-bar icon reflects progress.

## Inputs and events

`DictationPipeline.Input` carries the captured `AudioBuffer`, start timestamp, focused-app identifiers, whether polish is enabled for this run, polish prompt, timeouts, and audio-retention flags.

Events emitted (in order on success):

```
.transcribing → .polishing → .injecting → .done(DictationEntry)
```

Any stage can emit `.failed(String)` and stop. `.done` includes the fully-populated `DictationEntry` that was handed to `HistoryStore`.

## State machine mapping

`StateMachine` is the UI-side projection of pipeline progress. The transitions:

| Trigger | From → To |
|--------|-----------|
| hotkey press (idle) | `.idle` → `.recording` |
| hotkey release / toggle (recording) | `.recording` → `.transcribing` |
| pipeline `.polishing` | `.transcribing` → `.polishing` |
| pipeline `.injecting` | `.polishing` → `.injecting` |
| pipeline `.done` | `.injecting` → `.idle` |
| pipeline `.failed(msg)` | any → `.error(msg)` |
| hotkey press (error) | `.error` → `.idle` (one-press recovery) |

The `.transcribing` transition happens when the user stops recording, not on `.transcribing` emission — the pipeline's `.transcribing` event is redundant with the UI transition and is ignored in `AppDelegate.handlePipelineEvent`.

## Flow

1. **Capture.** `Recorder` installs an AVAudioEngine tap, converts the mic format to mono Float32 at 16 kHz inside the tap closure, and appends samples to `AudioBuffer` (a thread-safe ring).
2. **Transcribe.** `ASRService.transcribe(_:)` runs under `withTimeout(input.transcribeTimeout)`. WhisperKit holds the `whisper-large-v3-turbo` CoreML model resident and returns a `Transcript { text, language, segments }`.
3. **Save audio (optional).** If `input.saveAudio`, the buffer snapshot is written to `AudioStore` and old files are pruned.
4. **Polish.** If `input.polishEnabled` is true, `PolishService.polish(_:prompt:)` runs under `withTimeout(input.polishTimeout)`. On failure, the pipeline logs and falls back to the raw transcript — never aborts for a polish failure. If polish is disabled for the run, this stage is skipped and the raw transcript is used directly.
5. **Inject.** `TextInjector.inject(_:)` stages the text on the pasteboard and synthesizes ⌘V. Skipped cleanly when the polished text is empty.
6. **Persist.** A `DictationEntry` is inserted into `HistoryStore` (if configured).

## Timeouts

Shared helper: [`Support/PipelineTimeout.swift`](../../LocalTypeless/Support/PipelineTimeout.swift) — `withTimeout(_:_:)` races the operation against `Task.sleep` and throws `PipelineTimeoutError.timedOut`.

Default values in `AppDelegate.runPipeline()`:

- Transcribe: 60 s
- Polish: 30 s

Tests pass aggressive values (e.g. 0.1 s) to assert the timeout path emits `.failed("Transcription timed out")` and writes no history row.

## Failure handling

| Stage | On failure | User impact |
|-------|-----------|-------------|
| ASR throws / times out | `.failed("Transcription timed out")` or `.failed("ASR failed")`; no history row | `.error` state, red → yellow icon, recoverable with a hotkey press |
| Polish throws / times out | log + fall back to raw transcript; injection proceeds | History row stores `polishedText == rawTranscript` |
| Injection — accessibility denied | text stays on pasteboard | Warn log only; user pastes manually |
| Injection — other | log + swallow | Text still on pasteboard |
| Audio save | log + continue | Dictation still lands in history |
| History insert | swallowed | Dictation still injected |

The only case that produces a `.failed` event is ASR (including its timeout). Polish + injection + persistence are best-effort.
