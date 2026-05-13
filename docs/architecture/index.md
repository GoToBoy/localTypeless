# Architecture

local-typeless is a `LSUIElement` menu-bar app. A single `AppDelegate` wires dependencies at launch; the dictation loop is a self-contained async pipeline that emits events the UI maps to a finite state machine.

## Component map

```
┌──────────────────────────────────────────────────────────────────────┐
│  AppDelegate (@MainActor) — owns lifetimes, wires dependencies       │
│                                                                      │
│  HotkeyManager ── press/release ─┐                                   │
│  (Carbon / CGEventTap)           │                                   │
│                                  ▼                                   │
│  Recorder ── Float32 @16kHz ── AudioBuffer (thread-safe ring)        │
│  (AVAudioEngine tap)                                                 │
│                                                                      │
│  StateMachine      ◀── events ──  DictationPipeline                  │
│  (@Observable)                    @MainActor, single run() per call  │
│                                       │                              │
│                ┌──────────────────────┼──────────────────────┐       │
│                ▼                      ▼                      ▼       │
│        ASRService             PolishService           TextInjector   │
│        (WhisperKit)           (MLX / Qwen2.5-3B)     (pb + CGEvent)  │
│                │                      │                      │       │
│                ▼                      ▼                      ▼       │
│         Transcript          polished: String        paste into app   │
│                                       │                              │
│                                       ▼                              │
│                               HistoryStore          AudioStore        │
│                               (GRDB SQLite)         (WAV, optional)   │
│                                                                      │
│  ModelStatusStore ◀─── status updates ───  *ModelManaging managers   │
│  (@Observable)         (download / load / unload)                    │
│                                                                      │
│  MediaController — pauses Music/Spotify/etc. during recording        │
│  MenuBarController — icon states, dropdown menu                      │
│  PermissionChecker — mic / accessibility / input-monitoring          │
│  FirstRunState — onboarding-completed flag                           │
└──────────────────────────────────────────────────────────────────────┘
```

## Invariants

- **Single owner.** `AppDelegate` owns every long-lived service reference. Everything else takes them by dependency injection. No singletons.
- **Pipeline is stateless between runs.** `DictationPipeline.run(_:onEvent:)` takes all inputs as a struct and emits events; it holds no per-session state of its own.
- **StateMachine is UI-side.** It observes events from `DictationPipeline` but does not drive it. The pipeline can be tested end-to-end without a state machine.
- **No network in the dictation path.** Model download is a separate, user-initiated flow.
- **`@MainActor` by default.** Everything touching pipeline, settings, UI, or state runs on main. Services that cross actor boundaries are `Sendable`.

## Deeper reads

- [pipeline.md](pipeline.md) — end-to-end dictation flow, timeouts, failure branches.
- [models.md](models.md) — ASR + polish model lifecycle, RAM budget, status transitions.
- [hotkeys.md](hotkeys.md) — binding shapes, toggle vs push-to-talk, conflict detection.
