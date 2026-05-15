import SwiftUI

struct ModelDownloadView: View {
    @Bindable var store: ModelStatusStore
    let kind: ModelKind
    let onStart: () -> Void
    let onCancel: () -> Void

    private var title: String {
        switch (kind, store.status(for: kind)) {
        case (.asrWhisperLargeV3Turbo, .notDownloaded),
             (.asrWhisperLargeV3Turbo, .failed),
             (.asrWhisperCppSmall, .notDownloaded),
             (.asrWhisperCppSmall, .failed):
            return String(localized: "Download speech model")
        case (.asrWhisperLargeV3Turbo, .downloaded),
             (.asrWhisperCppSmall, .downloaded):
            return String(localized: "Speech model downloaded")
        case (.asrWhisperLargeV3Turbo, .downloading),
             (.asrWhisperCppSmall, .downloading):
            return String(localized: "Downloading speech model")
        case (.asrWhisperLargeV3Turbo, .loading),
             (.asrWhisperCppSmall, .loading):
            return String(localized: "Loading speech model")
        case (.asrWhisperLargeV3Turbo, .resident),
             (.asrWhisperCppSmall, .resident):
            return String(localized: "Speech model ready")

        case (.polishQwen25_3bInstruct4bit, .notDownloaded),
             (.polishQwen25_3bInstruct4bit, .failed):
            return String(localized: "Download polish model")
        case (.polishQwen25_3bInstruct4bit, .downloaded):
            return String(localized: "Polish model downloaded")
        case (.polishQwen25_3bInstruct4bit, .downloading):
            return String(localized: "Downloading polish model")
        case (.polishQwen25_3bInstruct4bit, .loading):
            return String(localized: "Loading polish model")
        case (.polishQwen25_3bInstruct4bit, .resident):
            return String(localized: "Polish model ready")
        }
    }

    private var subtitle: String {
        switch store.status(for: kind) {
        case .downloaded:
            return String(localized: "Ready for dictation · loads automatically")
        case .loading:
            return String(localized: "Loading from local disk")
        case .resident:
            return String(localized: "Loaded into memory")
        case .notDownloaded, .downloading, .failed:
            break
        }

        switch kind {
        case .asrWhisperLargeV3Turbo:
            return String(localized: "~1.5 GB · offline after download")
        case .polishQwen25_3bInstruct4bit:
            return String(localized: "~2 GB · offline after download")
        case .asrWhisperCppSmall:
            return String(localized: "~470 MB · offline after download")
        }
    }

    private var iconName: String {
        switch kind {
        case .asrWhisperLargeV3Turbo:       return "waveform"
        case .polishQwen25_3bInstruct4bit:   return "sparkles"
        case .asrWhisperCppSmall:           return "waveform"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: iconName)
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            statusRow

            Spacer(minLength: 12)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                actionButton
            }
        }
        .padding(24)
        .frame(width: 420, height: 220)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch store.status(for: kind) {
        case .notDownloaded:
            Label("Not downloaded yet", systemImage: "arrow.down.circle")
        case .downloading(let p):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: p)
                Text("Downloading… \(Int(p * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .downloaded:
            Label("Downloaded", systemImage: "externaldrive.fill.badge.checkmark")
        case .loading:
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading into memory…")
            }
        case .resident:
            Label("Ready", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch store.status(for: kind) {
        case .notDownloaded, .failed:
            Button("Download", action: onStart)
                .keyboardShortcut(.defaultAction)
        case .downloading, .loading:
            Button("Working…") {}.disabled(true)
        case .downloaded, .resident:
            Button("Done", action: onCancel)
                .keyboardShortcut(.defaultAction)
        }
    }
}
