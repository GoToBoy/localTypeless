import SwiftUI

struct SettingsGeneralTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Hotkey") {
                hotkeyRow
                modifierOnlyRow
                hotkeyModeRow
            }

            Section("Speech") {
                Picker("ASR language", selection: $settings.asrLanguageMode) {
                    Text("Auto-detect").tag(ASRLanguageMode.auto)
                    Text("English only").tag(ASRLanguageMode.en)
                    Text("Chinese only").tag(ASRLanguageMode.zh)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var hotkeyRow: some View {
        HStack {
            Text("Trigger shortcut")
            Spacer()
            HotkeyRecorderField(binding: $settings.hotkeyBinding)
                .frame(width: 180)
        }
    }

    @ViewBuilder
    private var hotkeyModeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Mode", selection: $settings.hotkeyMode) {
                Text("Toggle (press to start, press to stop)").tag(HotkeyMode.toggle)
                Text("Push-to-talk (hold to record)").tag(HotkeyMode.pushToTalk)
            }
            if settings.hotkeyMode == .pushToTalk
                && !HotkeyMode.pushToTalk.isSupported(by: settings.hotkeyBinding) {
                Text("Push-to-talk requires a modifier-only shortcut with the ‘Tap’ trigger; falling back to toggle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var modifierOnlyRow: some View {
        HStack {
            Text("Modifier-only")
            Spacer()
            Picker("", selection: $settings.hotkeyBinding) {
                Text("(none)").tag(HotkeyBinding(
                    keyCode: settings.hotkeyBinding.keyCode,
                    modifierMask: settings.hotkeyBinding.modifierMask,
                    trigger: .press, modifierOnly: nil))
                Text("Double-tap right ⌥").tag(HotkeyBinding(
                    keyCode: nil, modifierMask: [], trigger: .doubleTap, modifierOnly: .rightOption))
                Text("Double-tap left ⌥").tag(HotkeyBinding(
                    keyCode: nil, modifierMask: [], trigger: .doubleTap, modifierOnly: .leftOption))
                Text("Long-press right ⌃").tag(HotkeyBinding(
                    keyCode: nil, modifierMask: [], trigger: .longPress, modifierOnly: .rightControl))
            }
            .frame(width: 220)
        }
    }
}
