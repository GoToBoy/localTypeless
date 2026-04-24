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
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack {
                Text(binding.keyCode != nil ? binding.displayString : "—")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isRecording ? "Press keys…" : "Record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stopMonitor() }
    }

    private func toggleRecording() {
        if isRecording { stopMonitor() } else { startMonitor() }
    }

    private func startMonitor() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let mask = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard mask.isEmpty == false else {
                // A plain keydown with no modifiers is rejected (too prone to breaking).
                NSSound.beep()
                return event
            }
            let new = HotkeyBinding(
                keyCode: event.keyCode,
                modifierMask: mask,
                trigger: .press,
                modifierOnly: nil
            )
            binding = new
            onChange?(new)
            stopMonitor()
            return nil  // swallow the event
        }
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        isRecording = false
    }
}
