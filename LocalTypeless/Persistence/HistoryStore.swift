import Foundation

struct DictationEntry: Equatable {
    var id: Int64?
    let startedAt: Date
    let durationMs: Int
    let rawTranscript: String
    let polishedText: String
    let language: String
    let targetAppBundleId: String?
    let targetAppName: String?

    init(
        id: Int64? = nil,
        startedAt: Date,
        durationMs: Int,
        rawTranscript: String,
        polishedText: String,
        language: String,
        targetAppBundleId: String?,
        targetAppName: String?
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.rawTranscript = rawTranscript
        self.polishedText = polishedText
        self.language = language
        self.targetAppBundleId = targetAppBundleId
        self.targetAppName = targetAppName
    }
}

protocol HistoryStore {
    @discardableResult
    func insert(_ entry: DictationEntry) throws -> Int64
    func all() throws -> [DictationEntry]
    func search(query: String) throws -> [DictationEntry]
    func delete(id: Int64) throws
}
