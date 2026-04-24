import Foundation

/// How a hotkey press maps to record start/stop.
///
/// - `toggle`: press starts recording, press again stops. Works with every
///   binding shape (key+modifier, modifier-only with any trigger).
/// - `pushToTalk`: press-and-hold records, release stops. Requires a
///   modifier-only binding with the `.press` trigger — other configurations
///   silently fall back to toggle because Carbon key events and
///   `doubleTap`/`longPress` triggers don't expose a meaningful "release".
enum HotkeyMode: String, Codable, CaseIterable, Sendable {
    case toggle
    case pushToTalk

    /// Whether the chosen binding supports this mode natively. Push-to-talk
    /// only works on modifier-only bindings with the `.press` trigger.
    func isSupported(by binding: HotkeyBinding) -> Bool {
        switch self {
        case .toggle:
            return true
        case .pushToTalk:
            return binding.modifierOnly != nil && binding.trigger == .press
        }
    }

    /// The effective mode the HotkeyManager should apply, falling back to
    /// `.toggle` when the binding can't support the requested mode.
    func effective(for binding: HotkeyBinding) -> HotkeyMode {
        isSupported(by: binding) ? self : .toggle
    }
}
