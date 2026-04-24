import SwiftUI
import AppKit

/// A SwiftUI button that, when clicked, enters "recording" mode. While recording,
/// the next keyDown (with modifiers) is captured as a HotkeyBinding and passed
/// back via `onChange`. Modifier-only triggers (e.g. double-tap right Option)
/// are configured via the separate ModifierOnlyPicker; this field only captures
/// key+modifier combos.
struct HotkeyRecorderField: View {

    @Binding var binding: HotkeyBinding
    var onChange: ((HotkeyBinding) -> Void)?

    @State private var isRecording = false

    var body: some View {
        ZStack {
            // Invisible capture view is installed only while recording so it
            // steals firstResponder, receives keyDown from the window, and
            // escapes after a single capture.
            if isRecording {
                HotkeyCaptureView(
                    onCapture: { captured in
                        binding = captured
                        onChange?(captured)
                        isRecording = false
                    },
                    onCancel: { isRecording = false }
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            Button(action: { isRecording.toggle() }) {
                HStack {
                    Text(binding.keyCode != nil ? binding.displayString : "—")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // BUG-L03 fix: a ternary expression `condition ? "a" : "b"`
                    // is inferred as String, which makes Text select the non-
                    // localizing Text(_ content: String) overload.  Using two
                    // separate Text literals lets Swift pick Text(_ key: LocalizedStringKey).
                    if isRecording {
                        Text("Press keys…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Record")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.3))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// NSView-backed capture surface. Becomes first responder on attach and
/// translates the next keyDown with modifiers into a HotkeyBinding.
///
/// Why not `NSEvent.addLocalMonitorForEvents`: SwiftUI's Form/Button responder
/// chain can intercept keyDown events before a local monitor sees them,
/// causing the field to appear "dead" on press. A custom NSView that sits
/// directly in the window's responder chain and overrides `keyDown(_:)` is
/// the stable approach used by all modern recorder UIs.
private struct HotkeyCaptureView: NSViewRepresentable {
    let onCapture: (HotkeyBinding) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = CaptureNSView()
        v.onCapture = onCapture
        v.onCancel = onCancel
        // Defer firstResponder until the view is attached to a window.
        DispatchQueue.main.async { [weak v] in
            _ = v?.window?.makeFirstResponder(v)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? CaptureNSView else { return }
        v.onCapture = onCapture
        v.onCancel = onCancel
        if v.window?.firstResponder !== v {
            DispatchQueue.main.async { [weak v] in
                _ = v?.window?.makeFirstResponder(v)
            }
        }
    }

    final class CaptureNSView: NSView {
        var onCapture: ((HotkeyBinding) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }
        override func becomeFirstResponder() -> Bool { true }

        override func keyDown(with event: NSEvent) {
            // Escape cancels without binding.
            if event.keyCode == 53 {
                onCancel?()
                return
            }
            let mask = event.modifierFlags.intersection(
                [.command, .option, .control, .shift]
            )
            guard !mask.isEmpty else {
                // Plain key without modifier is rejected — too likely to
                // break normal typing and too easy to trigger by accident.
                NSSound.beep()
                return
            }
            let binding = HotkeyBinding(
                keyCode: event.keyCode,
                modifierMask: mask,
                trigger: .press,
                modifierOnly: nil
            )
            onCapture?(binding)
        }

        // Swallow flagsChanged/keyUp while recording so the window's normal
        // responder chain doesn't interpret them as navigation.
        override func flagsChanged(with event: NSEvent) {}
    }
}
