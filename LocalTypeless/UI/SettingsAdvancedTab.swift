import SwiftUI

struct SettingsAdvancedTab: View {
    @Bindable var settings: AppSettings
    let modelStatusStore: ModelStatusStore
    let requiredModelKinds: [ModelKind]
    let polishAvailable: Bool
    let onDownload: (ModelKind) -> Void
    let firstRunState: FirstRunState
    let onReopenOnboarding: () -> Void

    var body: some View {
        Form {
            Section("Paste behavior") {
                Picker("Paste method", selection: $settings.pasteMethod) {
                    Text("Synthesize ⌘V (fast, default)").tag(PasteMethod.cgEvent)
                    Text("AppleScript (needs Automation)").tag(PasteMethod.appleScript)
                }
                Toggle("Preserve clipboard after paste", isOn: $settings.preserveClipboard)
                Text("If an app filters synthesized key events or your keyboard layout rewrites ⌘-layer keys, try the AppleScript method.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recording") {
                Toggle("Pause media while recording", isOn: $settings.pauseMediaDuringRecording)
                Text("Pauses Music, Spotify, or browser audio during recording so the microphone doesn't capture playback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Audio retention") {
                Toggle("Keep raw audio on disk", isOn: $settings.audioRetentionEnabled)
                Stepper(value: $settings.audioRetentionDays, in: 1...30) {
                    Text("Keep for \(settings.audioRetentionDays) day(s)")
                }
                .disabled(!settings.audioRetentionEnabled)
            }

            Section("Models") {
                if polishAvailable {
                    Picker("Polish", selection: $settings.polishMode) {
                        Text("Automatic").tag(PolishMode.automatic)
                        Text("On").tag(PolishMode.on)
                        Text("Off").tag(PolishMode.off)
                    }
                    Text(polishMemorySummary())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(requiredModelKinds, id: \.self) { kind in
                    let polishDisabled = (kind == .polishQwen25_3bInstruct4bit
                                          && settings.polishMode == .off)
                    modelRow(
                        label: kind.displayName,
                        status: modelStatusStore.status(for: kind),
                        isDisabled: polishDisabled,
                        onDownload: { onDownload(kind) }
                    )
                }
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
    private func modelRow(label: String,
                           status: ModelStatus,
                           isDisabled: Bool = false,
                           onDownload: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label)
                Text(isDisabled ? String(localized: "Disabled") : describe(status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDisabled {
                EmptyView()
            } else {
                switch status {
                case .resident:
                    Label("Ready", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                case .downloaded:
                    EmptyView()
                case .downloading, .loading:
                    Button("Working…") {}.disabled(true)
                case .notDownloaded, .failed:
                    Button("Download", action: onDownload)
                }
            }
        }
    }

    private func polishMemorySummary() -> String {
        let snapshot = MemoryAdvisor.currentSnapshot()
        let memoryLine = String(
            format: String(localized: "Memory now: %@ available of %@."),
            snapshot.availableDescription,
            snapshot.totalDescription
        )
        let policy = String(localized: "Automatic skips polish when memory is tight.")
        return "\(memoryLine) \(policy)"
    }

    private func describe(_ s: ModelStatus) -> String {
        switch s {
        case .notDownloaded:        return String(localized: "Not downloaded")
        case .downloading(let p):   return String(localized: "Downloading… \(Int(p * 100))%")
        case .downloaded:           return String(localized: "Downloaded (loads automatically)")
        case .loading:              return String(localized: "Loading…")
        case .resident:             return String(localized: "Ready")
        case .failed(let m):        return String(localized: "Failed: \(m)")
        }
    }
}
