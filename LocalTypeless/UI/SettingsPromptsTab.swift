import SwiftUI

struct SettingsPromptsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Polish prompt") {
                Text("Empty = use the default for the detected language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $settings.polishPromptOverride)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3))
                    )

                HStack {
                    Spacer()
                    Button("Reset to default") { settings.resetPolishPrompt() }
                        .disabled(settings.polishPromptOverride.isEmpty)
                }
            }

            Section("Defaults (read-only)") {
                DisclosureGroup("English") {
                    Text(DefaultPrompts.polishEN)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                DisclosureGroup("中文") {
                    Text(DefaultPrompts.polishZH)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}
