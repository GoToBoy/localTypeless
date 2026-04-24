import SwiftUI

struct SettingsGeneralTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Hotkey") {
                hotkeyRow
                modifierOnlyRow
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
    private var modifierOnlyRow: some View {
        HStack {
            Text("Modifier-only")
            Spacer()
            // BUG-F01 fix: the former "(none)" option produced a HotkeyBinding
            // with both keyCode == nil and modifierOnly == nil, which caused
            // HotkeyManager to silently drop the binding with no user feedback.
            // There is no valid "no-trigger" use case, so the option is removed.
            Picker("", selection: $settings.hotkeyBinding) {
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
