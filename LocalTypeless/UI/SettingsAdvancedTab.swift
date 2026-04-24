import SwiftUI

struct SettingsAdvancedTab: View {
    @Bindable var settings: AppSettings
    let modelStatusStore: ModelStatusStore
    let onDownloadAsr: () -> Void
    let onDownloadPolish: () -> Void
    let firstRunState: FirstRunState
    let onReopenOnboarding: () -> Void

    var body: some View {
        Form {
            Section("Audio retention") {
                Toggle("Keep raw audio on disk", isOn: $settings.audioRetentionEnabled)
                Stepper(value: $settings.audioRetentionDays, in: 1...30) {
                    Text("Keep for \(settings.audioRetentionDays) day(s)")
                }
                .disabled(!settings.audioRetentionEnabled)
            }

            Section("Models") {
                modelRow(
                    label: "Speech (Whisper Large v3 Turbo)",
                    status: modelStatusStore.status(for: .asrWhisperLargeV3Turbo),
                    onDownload: onDownloadAsr
                )
                modelRow(
                    label: "Polish (Qwen2.5-3B-Instruct 4bit)",
                    status: modelStatusStore.status(for: .polishQwen25_3bInstruct4bit),
                    onDownload: onDownloadPolish
                )
            }

            Section(String(localized: "First-run experience")) {
                Button(String(localized: "Reopen welcome tour…")) {
                    firstRunState.reset()
                    onReopenOnboarding()
                }
            }

            Section(String(localized: "Interface language")) {
                Picker(String(localized: "Language"), selection: $settings.uiLanguageMode) {
                    Text("System").tag(UILanguageMode.system)
                    Text("English").tag(UILanguageMode.en)
                    Text("简体中文").tag(UILanguageMode.zhHans)
                }
                Text(String(localized: "Restart the app to see the change everywhere."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    // BUG-L02 fix: use LocalizedStringKey so Text(label) resolves to
    // Text(_ key: LocalizedStringKey) and looks up the xcstrings catalog.
    // A String parameter would select Text(_ content: String) which skips
    // localization even when the literal key exists in the catalog.
    private func modelRow(label: LocalizedStringKey,
                           status: ModelStatus,
                           onDownload: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label)
                Text(describe(status)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Only offer "Download" when the model is genuinely missing.
            // A Download button sitting next to "Loading…" (the common
            // post-restart state while weights warm into RAM) is
            // misleading — same distinction applied in the menu bar and
            // the hotkey gate.
            switch status {
            case .resident:
                Label("Ready", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            case .downloading, .loading:
                ProgressView().controlSize(.small)
            case .downloaded:
                Label("On disk", systemImage: "externaldrive.fill.badge.checkmark")
                    .foregroundStyle(.secondary)
            case .notDownloaded, .failed:
                Button("Download", action: onDownload)
            }
        }
    }

    private func describe(_ s: ModelStatus) -> String {
        switch s {
        case .notDownloaded:        return String(localized: "Not downloaded")
        case .downloading(let p):   return String(localized: "Downloading… \(Int(p * 100))%")
        case .downloaded:           return String(localized: "Downloaded (not loaded)")
        case .loading:              return String(localized: "Loading…")
        case .resident:             return String(localized: "Ready")
        case .failed(let m):        return String(localized: "Failed: \(m)")
        }
    }
}
