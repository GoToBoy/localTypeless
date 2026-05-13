# Hotkeys

Two things determine how a press fires:

- **Binding shape** (`HotkeyBinding`) — which physical keys + what trigger rule.
- **Mode** (`HotkeyMode`) — toggle vs push-to-talk.

## Binding shapes

`HotkeyBinding` covers two disjoint shapes:

1. **Key + modifiers.** Any `keyCode` with zero or more of ⌘ ⇧ ⌃ ⌥ (e.g. `⌘⇧D`).
2. **Modifier-only.** One of `leftCommand`, `rightCommand`, `leftOption`, `rightOption`, `leftControl`, `rightControl`, `leftShift`, `rightShift`, `fn`, with a trigger of:
   - `.press` — single tap (fires on modifier-down)
   - `.doubleTap` — two taps within ~300 ms
   - `.longPress` — hold past a threshold

Default is **double-tap right ⌥**.

Left/right modifier variants are distinguished. The menu bar's "Hotkey recorder" field in Settings captures whatever the user presses.

## Mode semantics

| Mode | Binding constraints | Behavior |
|------|--------------------|-------|
| `.toggle` | any shape | press starts recording; next press stops and runs the pipeline |
| `.pushToTalk` | modifier-only, `.press` trigger only | press-and-hold records; release stops and runs the pipeline |

`HotkeyMode.effective(for:)` falls back to `.toggle` when the binding can't support push-to-talk natively (e.g. key+modifier, or any `.doubleTap`/`.longPress` trigger). This is because Carbon `RegisterEventHotKey` and synthetic tap triggers don't expose a meaningful "release" event.

## Two registration paths

`HotkeyManager` chooses one based on the binding:

- **Carbon `RegisterEventHotKey`** for key + modifier bindings. Fires once per press.
- **`CGEventTap`** for modifier-only bindings. Needs the manager to track modifier state over time to synthesize `.press` / `.doubleTap` / `.longPress` / `.release`.

Both paths invoke the same `onPress` / `onRelease` closures.

## Conflict detection

Before persisting a new binding, Settings calls `HotkeyManager.probe(_:)` (test-register). If installation fails (usually another app owns the shortcut), the UI surfaces an inline warning; the user can still force-save.

## One-press error recovery

When `StateMachine.state == .error`, a hotkey press transitions to `.idle` (the fail branch stops there — it does not immediately start recording). The next press records. This avoids a stuck `.error` that requires a Settings round-trip.
