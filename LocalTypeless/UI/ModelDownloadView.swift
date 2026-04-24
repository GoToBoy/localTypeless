import SwiftUI

struct ModelDownloadView: View {
    @Bindable var store: ModelStatusStore
    let kind: ModelKind
    let onStart: () -> Void
    let onCancel: () -> Void

    // BUG-L01 fix: use LocalizedStringKey so Text(title) / Text(subtitle) resolve
    // to Text(_ key: LocalizedStringKey) and look up the xcstrings catalog.
    // Returning a plain String would select Text(_ content: String) which skips
    // localization even when the literal exists in the catalog.
    private var title: LocalizedStringKey {
        switch kind {
        case .asrWhisperLargeV3Turbo:       return "Download speech model"
        case .polishQwen25_3bInstruct4bit:   return "Download polish model"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch kind {
        case .asrWhisperLargeV3Turbo:       return "~1.5 GB · offline after download"
        case .polishQwen25_3bInstruct4bit:   return "~2 GB · offline after download"
        }
    }

    private var iconName: String {
        switch kind {
        case .asrWhisperLargeV3Turbo:       return "waveform"
        case .polishQwen25_3bInstruct4bit:   return "sparkles"
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
            Label("Downloaded (not loaded)", systemImage: "externaldrive.fill.badge.checkmark")
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
        case .downloaded:
            Button("Load", action: onStart)
                .keyboardShortcut(.defaultAction)
        case .resident:
            Button("Done", action: onCancel)
                .keyboardShortcut(.defaultAction)
        }
    }
}
