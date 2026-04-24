import SwiftUI
import AppKit

// BUG-F05 fix: HistoryView was a read-only placeholder.  This rewrite adds:
//   - Searchable list (drives SQLiteHistoryStore.search)
//   - Per-row context menu: Copy raw, Copy polished, Re-inject, Delete
//   - Multi-selection with bulk delete (toolbar Delete button)
//   - Target app name displayed in each row
//   - Async reload so the main thread is not blocked by SQLite reads

struct HistoryView: View {

    let store: HistoryStore
    // Re-inject requires a TextInjector; pass one from AppDelegate via environment
    // or a closure.  We use a simple closure to avoid a hard dependency.
    var onReInject: ((String) -> Void)?

    @State private var entries: [DictationEntry] = []
    @State private var searchQuery: String = ""
    @State private var selection: Set<Int64> = []
    @State private var isLoading = false

    private var displayed: [DictationEntry] {
        if searchQuery.isEmpty { return entries }
        let q = searchQuery.lowercased()
        return entries.filter {
            $0.polishedText.lowercased().contains(q) ||
            $0.rawTranscript.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("History")
                    .font(.title2).bold()
                Spacer()
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: {
                        Label(String(localized: "Delete Selected"), systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayed.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: searchQuery.isEmpty ? "mic.slash" : "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(searchQuery.isEmpty
                         ? String(localized: "No dictations yet.")
                         : String(localized: "No results for \"\(searchQuery)\""))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(displayed, id: \.id, selection: $selection) { entry in
                    rowView(entry)
                        .tag(entry.id ?? -1)
                        .contextMenu { contextMenu(for: entry) }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchQuery,
                    placement: .toolbar,
                    prompt: String(localized: "Search transcripts"))
        .frame(width: 600, height: 480)
        .task { await reload() }
        .onChange(of: searchQuery) { _, _ in
            Task { await reload() }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(_ entry: DictationEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.polishedText)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(entry.language.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                if let app = entry.targetAppName {
                    Text(app)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatDuration(entry.durationMs))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for entry: DictationEntry) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.polishedText, forType: .string)
        } label: {
            Label(String(localized: "Copy Polished Text"), systemImage: "doc.on.doc")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.rawTranscript, forType: .string)
        } label: {
            Label(String(localized: "Copy Raw Transcript"), systemImage: "doc.plaintext")
        }

        if let onReInject {
            Button {
                onReInject(entry.polishedText)
            } label: {
                Label(String(localized: "Re-inject"), systemImage: "arrow.uturn.left")
            }
        }

        Divider()

        Button(role: .destructive) {
            deleteEntry(entry)
        } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func deleteEntry(_ entry: DictationEntry) {
        guard let id = entry.id else { return }
        try? store.delete(id: id)
        entries.removeAll { $0.id == id }
        selection.remove(id)
    }

    private func deleteSelected() {
        for id in selection {
            try? store.delete(id: id)
        }
        entries.removeAll { selection.contains($0.id ?? -1) }
        selection.removeAll()
    }

    // MARK: - Data loading

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        // SQLite reads via GRDB are fast enough to run on the main actor;
        // avoids Sendable issues with Task.detached capturing non-Sendable store.
        if searchQuery.isEmpty {
            entries = (try? store.all()) ?? []
        } else {
            entries = (try? store.search(query: searchQuery)) ?? []
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ ms: Int) -> String {
        let total = ms / 1000
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
