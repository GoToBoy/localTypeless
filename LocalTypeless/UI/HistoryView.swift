import SwiftUI

struct HistoryView: View {

    @State private var entries: [DictationEntry] = []
    let store: HistoryStore

    var body: some View {
        VStack(alignment: .leading) {
            Text("History").font(.title).padding(.bottom, 8)
            if entries.isEmpty {
                Text("No dictations yet.").foregroundStyle(.secondary)
            } else {
                List(entries, id: \.id) { e in
                    VStack(alignment: .leading) {
                        Text(e.polishedText).font(.body)
                        Text("\(languageLabel(for: e)) · \(e.startedAt.formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(width: 560, height: 420)
        .task { reload() }
    }

    private func reload() {
        entries = (try? store.all()) ?? []
    }

    private func languageLabel(for entry: DictationEntry) -> String {
        switch TranscriptLanguage.normalized(reported: entry.language, text: entry.polishedText) {
        case "zh":
            return String(localized: "中文")
        case "en":
            return String(localized: "English")
        case let code:
            return code.uppercased()
        }
    }
}
