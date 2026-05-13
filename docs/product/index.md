# Product

What the user sees and can configure.

## Core loop

1. Press the global hotkey (default: double-tap right ⌥).
2. Speak. The menu-bar icon turns red while recording.
3. Press again (toggle) or release (push-to-talk). Icon progresses through pulsing blue (transcribing) → pulsing purple (polishing) → brief green (injecting).
4. Polished text is pasted into the app that was focused when recording started.
5. A history entry is written. Open History from the menu to search past transcripts.

Fully offline after the initial model download. No telemetry, no network calls in the dictation path.

## Menu bar

Status icon reflects `DictationState`:

| State | Icon |
|-------|------|
| `.idle` | neutral mic |
| `.recording` | red dot |
| `.transcribing` | pulsing blue |
| `.polishing` | pulsing purple |
| `.injecting` | brief green flash (<200 ms, usually invisible) |
| `.error` | yellow warning; tooltip carries the last message |

Dropdown: **Open History**, **Open Settings**, **Unload models**, **Quit**.

## Settings

Four tabs: **General**, **Prompts**, **Advanced**, and a Models status panel embedded in General.

### General
- **Hotkey recorder** — capture any key+modifier or modifier-only tap/double-tap/long-press. Conflicts surface inline.
- **Hotkey mode** — Toggle / Push-to-talk. Push-to-talk is disabled unless the binding is modifier-only with `.press`.
- **ASR language** — Auto / English / Chinese. `Auto` lets Whisper detect.
- **UI language** — System / English / 简体中文. Applied on next launch for full effect.
- **Pause media while recording** — uses `MediaController` to pause apps like Music / Spotify on record-start, resume on record-stop.
- **Launch at login** — toggles via `SMAppService` (see `Settings/LaunchAtLogin.swift`).
- **Paste method** — `cgEvent` (default, low-latency) or `appleScript` (falls back via `System Events`).
- **Preserve clipboard** — save and restore the user's clipboard around the paste.

### Prompts
- Editor for the polish prompt, pre-populated with the localized default from `DefaultPrompts`. **Reset to default** restores the localized default.

### Advanced
- **Audio retention** — when enabled, raw WAV is written to `AudioStore` with a rolling N-day cleanup (default 7).
- **Reopen welcome tour** — re-launches `OnboardingView` for walking through permissions again.
- **Model status** — per-model state and **Unload** buttons.

## History window

- List sorted by date desc, full-text search across raw + polished transcripts.
- Per row: timestamp, target app name, polished-text preview, language tag.
- Row actions: **Copy raw**, **Copy polished**, **Re-inject**, **Delete**.

## Onboarding

First launch opens `OnboardingView`. The flow walks through Microphone, Accessibility, and Input Monitoring permission grants, with deep-links into the relevant panes of System Settings. `FirstRunState.onboardingCompleted` is flipped once the user finishes; **Settings → Advanced → Reopen welcome tour** resets it on demand.

## V1 limitations

- **Whisper download progress is coarse.** WhisperKit only reports 0 or 1 — the progress bar jumps. Polish (MLX) reports continuous progress.
- **No real-time streaming output.** Text is injected once after transcribe + polish. The pipeline is not streaming in v1.
- **No cloud sync.** History is local-only.
- **No iOS companion.**
- **No per-app custom vocabulary or per-hotkey prompt profiles.**
