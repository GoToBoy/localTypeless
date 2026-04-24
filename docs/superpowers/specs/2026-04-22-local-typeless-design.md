# local-typeless — Design Spec

**Date:** 2026-04-22
**Status:** Approved for implementation planning
**Target hardware:** Mac mini (Apple Silicon), 16 GB unified memory
**Target OS:** macOS 14+

## 1. Product summary

A native macOS menu-bar dictation app. User taps a global hotkey to start recording, taps again to stop. Audio is transcribed locally (English + Chinese auto-detected), then polished by a local LLM, then injected into the currently-focused app's text field. A history window preserves past transcripts.

Fully offline after initial model download. No network calls in the dictation path.

Inspired by Typeless; references: `soniqo/speech-swift`, `moonshine-ai/moonshine`, Qwen3-ASR.

## 2. Goals and non-goals

### Goals (v1 / MVP)
- Toggle-style global hotkey activation
- Local speech-to-text supporting English and Chinese (mixed OK)
- Local LLM polish step (filler removal, punctuation, formatting) with user-editable prompt
- Direct text injection into the focused macOS application
- Searchable history window
- Runs within the 16 GB RAM budget of a Mac mini base config
- Works offline
- **Bilingual UI**: all app UI (menu bar, Settings, History, onboarding, notifications) localized in English and Simplified Chinese, following the macOS system language by default with a manual override

### Non-goals (v1)
- iOS or iPadOS client
- Cloud sync of history
- Push-to-talk activation (may add in v2 via settings)
- Custom vocabularies / fine-tuning
- Real-time streaming output into the focused app (final text is injected once, after polish)
- Multi-user profiles

## 3. Technology stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| App shell | Swift 5.9+, SwiftUI + AppKit | Native, low RAM overhead, required for global hotkey + accessibility APIs |
| Localization | Xcode String Catalogs (`.xcstrings`) for `en` and `zh-Hans` | Modern unified format, supports pluralization and device variants, fits Swift 5.9+ toolchain |
| ASR | WhisperKit + `whisper-large-v3-turbo` CoreML | Apple Silicon optimized, multilingual (EN+ZH), ~1.5 GB RAM, Swift-native |
| LLM polish | MLX Swift + Qwen2.5-3B-Instruct 4-bit | Swift-native on-device inference, ~2 GB RAM, strong EN+ZH rewriting |
| Persistence | SQLite via GRDB.swift | Battle-tested Swift ORM with migrations |
| Hotkey | Carbon Event Manager + CGEventTap | Carbon for key+modifier combos, CGEventTap for modifier-only triggers |
| Audio | AVAudioEngine | Standard macOS capture, low latency |
| Text injection | NSPasteboard + CGEvent (Cmd+V) with AXUIElement fallback | Works in virtually every macOS app |

**Memory budget under load:**
- WhisperKit model resident: ~1.5 GB
- MLX LLM resident: ~2 GB
- App + buffers + overhead: ~0.5 GB
- **Total active:** ~4 GB — leaves >10 GB headroom on a 16 GB Mac mini.

**Models are lazy-loaded** (loaded on first dictation, kept resident for the session) and can be unloaded from the menu when idle to free RAM.

## 4. Architecture

```
┌───────────────────────────────────────────────────────────────┐
│  macOS app (SwiftUI + AppKit, LSUIElement menu-bar app)       │
│                                                                │
│  ┌──────────────┐  ┌────────────┐  ┌──────────────────────┐   │
│  │ HotkeyMgr    │→ │ Recorder   │→ │ AudioBuffer (PCM)    │   │
│  │ (Carbon API) │  │ (AVAudio)  │  │ 16kHz mono Float32   │   │
│  └──────────────┘  └────────────┘  └─────────┬────────────┘   │
│                                              │                 │
│                         ┌────────────────────┘                 │
│                         ▼                                      │
│                   ┌──────────────┐                             │
│                   │ ASRService   │  protocol (swappable)       │
│                   │ WhisperKit   │                             │
│                   └──────┬───────┘                             │
│                          ▼ raw transcript                      │
│                   ┌──────────────┐                             │
│                   │ PolishService│  protocol (swappable)       │
│                   │ MLX Swift    │                             │
│                   │ Qwen2.5-3B   │                             │
│                   └──────┬───────┘                             │
│                          ▼ polished text                       │
│            ┌─────────────┴──────────────┐                     │
│            ▼                            ▼                      │
│  ┌──────────────────┐        ┌──────────────────┐             │
│  │ TextInjector     │        │ HistoryStore     │             │
│  │ Pasteboard +     │        │ SQLite / GRDB    │             │
│  │ CGEvent Cmd+V    │        │                  │             │
│  └──────────────────┘        └──────────────────┘             │
│                                                                │
│  Menu-bar UI ──── Settings window ──── History window          │
└───────────────────────────────────────────────────────────────┘
```

### Protocol boundaries

Both `ASRService` and `PolishService` are Swift protocols with a single concrete implementation each for v1. This keeps the door open to:
- Swap in Qwen3-ASR when a stable Mac-native port exists
- Inject mocks in unit tests
- Offer user-selectable model backends later

```swift
protocol ASRService {
    func transcribe(_ audio: AudioBuffer) async throws -> Transcript
}

struct Transcript {
    let text: String
    let language: String  // BCP-47
    let segments: [Segment]
}

protocol PolishService {
    func polish(_ transcript: Transcript, prompt: String) async throws -> String
}
```

## 5. Core components

### 5.1 HotkeyManager
Registers a global hotkey via Carbon `RegisterEventHotKey` (for standard key+modifier combos) or `CGEventTap` (for modifier-only triggers). Default: double-tap of right Option within 300 ms.

**User-definable hotkeys.** Settings provides a "Record shortcut" field that captures whatever the user presses, supporting:
- Any single key + one or more modifiers (e.g. `⌃⌥Space`, `⌘⇧D`)
- Modifier-only triggers: single tap, double-tap, or long-press of any of `⌘` / `⌥` / `⌃` / `⇧` / `fn` (left or right variants distinguished)
- A short list of function keys and media keys where the system allows capture

The selected binding is persisted to `UserDefaults` as a `HotkeyBinding` struct (`keyCode`, `modifierMask`, `trigger: .press | .doubleTap | .longPress`, `side: .left | .right | .any`). On settings change the manager tears down the old binding and installs the new one atomically.

**Conflict detection.** Before saving, the manager test-registers the binding and, if it fails (e.g. another app owns it), surfaces an inline warning with the conflicting shortcut highlighted. The user can still force-save.

The manager emits a single `.toggle` event per activation to the state machine.

### 5.2 Recorder
Wraps `AVAudioEngine`. Captures 16 kHz mono Float32 PCM via an input tap. Writes to an in-memory `AudioBuffer` (ring buffer sized to ~2 minutes max recording). Voice Activity Detection is delegated to WhisperKit's built-in VAD — the Recorder just captures.

### 5.3 ASRService (WhisperKit implementation)
Loads `openai_whisper-large-v3-turbo` in CoreML format. Transcribes the full audio buffer after recording stops (not streaming in v1 — simpler, and the polish step has to wait for the full transcript anyway). Returns language-detected transcript.

### 5.4 PolishService (MLX Swift implementation)
Loads Qwen2.5-3B-Instruct-4bit (MLX format) from HuggingFace cache. Runs the raw transcript through a user-editable system prompt. Default prompt:

> You are a dictation cleanup assistant. Rewrite the user's speech by:
> 1. Removing filler words (um, uh, 呃, 嗯, like, you know)
> 2. Fixing punctuation and capitalization
> 3. Preserving the speaker's meaning and tone exactly
> 4. Keeping the language of the original (do not translate)
> Output only the cleaned text, no commentary.

Max output tokens: 2× input token count (prevents runaway generations). If polish fails, fall back to raw transcript.

### 5.5 TextInjector
1. Copy polished text to `NSPasteboard.general`
2. Synthesize `Cmd+V` via `CGEvent` targeting the focused app
3. After a short delay, restore previous pasteboard contents
4. Fallback path: if Accessibility permission is denied, leave on pasteboard and show a notification

### 5.6 HistoryStore
SQLite via GRDB. Single table:

```sql
CREATE TABLE dictation (
    id INTEGER PRIMARY KEY,
    started_at TEXT NOT NULL,
    duration_ms INTEGER NOT NULL,
    raw_transcript TEXT NOT NULL,
    polished_text TEXT NOT NULL,
    language TEXT NOT NULL,
    target_app_bundle_id TEXT,
    target_app_name TEXT
);
CREATE INDEX idx_dictation_started_at ON dictation(started_at DESC);
```

Audio files are **not** stored by default. If the user enables audio retention in Settings, raw audio is saved to `~/Library/Application Support/local-typeless/audio/<id>.wav` with a rolling 7-day cleanup.

### 5.7 Menu-bar UI
- Status icon states, matching the state machine in section 6:
  - `idle` — neutral mic glyph
  - `recording` — red dot
  - `transcribing` — pulsing blue
  - `polishing` — pulsing purple
  - `injecting` — flashes green briefly (<200 ms, usually not visible)
  - `error` — yellow warning; tooltip shows last error
- Dropdown menu: Open History, Settings, Unload models, Quit

### 5.8 Settings window
- Hotkey selector (record-shortcut field supporting any key+modifiers, plus modifier-only tap/double-tap/long-press)
- ASR language mode: Auto / English only / Chinese only
- **App UI language**: System default / English / 简体中文
- Polish prompt editor (with Reset-to-default; default prompts shipped in both EN and ZH)
- Model selection (for v1 only one choice each; UI scaffolded for future)
- Audio retention toggle + rolling window
- Launch at login toggle

### 5.9 History window
- List view sorted by date desc, with search
- Row: timestamp, target app icon, polished text (first line), language tag
- Actions per row: Copy raw, Copy polished, Re-inject, Delete
- Shift-select for bulk delete

## 6. Data flow — a single dictation session

1. User taps hotkey → `HotkeyManager` posts `.toggle` → state machine transitions `idle → recording` → menu icon turns red
2. `AVAudioEngine` input tap streams 16 kHz mono Float32 chunks into `AudioBuffer`
3. User taps hotkey → state `recording → transcribing` → audio buffer handed to `ASRService`
4. WhisperKit returns `Transcript { text, language, segments }`
5. State `transcribing → polishing` → `PolishService.polish()` with the user's prompt
6. State `polishing → injecting` → `TextInjector.inject(text)` writes to pasteboard + synthesizes Cmd+V
7. `HistoryStore.insert(...)` persists the row
8. State `injecting → idle` — menu icon returns to idle; total elapsed time shown as transient tooltip

Failure branches:
- If ASR throws: state → `error`, no history row, red icon clears on next hotkey press
- If polish throws: inject raw transcript, save history row with `polished_text = raw_transcript`, show warning icon once
- If injection fails (Accessibility denied): leave on pasteboard, post macOS notification "Transcript copied — paste manually"

## 7. Permissions

Requested on first launch, with a guided onboarding screen explaining each:
- **Microphone** — required; blocks recording if denied
- **Accessibility** — required for text injection and for the global hotkey monitor; app still works with clipboard-only fallback if denied
- **Input Monitoring** — required on macOS 10.15+ for global hotkey capture

If Accessibility is denied, the history window and copy-to-clipboard paths still work, so the app is never fully bricked.

## 8. Error handling

| Failure | Handling |
|---------|----------|
| Model download fails | Retry UI in Settings with progress and error detail |
| Model load fails (corrupted) | Offer re-download; log full error |
| Mic permission denied | Onboarding blocks until granted; menu item to reopen System Settings |
| ASR throws | Transient error state on menu icon; log to `~/Library/Logs/local-typeless/` |
| Polish throws / times out (>10s) | Fall back to raw transcript, warning icon |
| Injection throws | Fall back to clipboard-only with notification |
| Hotkey collision with another app | Settings shows a conflict warning; user picks a different key |

All failures are logged with timestamp, component, and stack trace to a rotating log file.

## 9. Testing strategy

### Unit tests
- `ASRService`, `PolishService`, `TextInjector`, `HistoryStore` all behind protocols with mocks
- `HotkeyManager` tested via injected event source
- Localization: snapshot test that asserts every `String(localized:)` key used in the codebase has both `en` and `zh-Hans` translations in the String Catalog (fails CI on missing keys)
- No real model loads in unit tests — fixtures only
- Target: ≥80% line coverage on non-UI code

### Integration tests
- Fixed 5-second `.wav` samples (one EN, one ZH, one mixed) committed to the test bundle
- Assert: transcript non-empty, contains expected keywords, polish removes a known filler
- Runs on CI with the CoreML + MLX model artifacts cached

### Manual QA matrix (pre-release)
- Speech: EN, ZH, mixed, with and without background noise
- Target apps: TextEdit, Safari address bar, VS Code, Slack, Messages, Notes
- Permission paths: grant all, deny Accessibility, deny Mic, deny Input Monitoring

## 10. Development workflow

- **Planning & architecture (this spec + plan):** Opus 4.7 Extra High
- **Coding:** Sonnet subagents dispatched via the superpowers `subagent-driven-development` skill for independent, well-scoped tasks
- **Review:** Codex for code review before commit
- Plans are written as phased Markdown docs in `docs/superpowers/plans/` per the superpowers workflow.

## 11. Out-of-scope follow-ups (parking lot)

- Push-to-talk mode
- Qwen3-ASR backend once a stable MLX / ggml port lands
- iOS companion (record on phone → transcript synced to Mac via iCloud)
- Custom vocabulary injection into the polish prompt
- Export history to Markdown / CSV
- Multi-hotkey profiles (e.g. different prompt per hotkey for "email mode" vs "code comment mode")
