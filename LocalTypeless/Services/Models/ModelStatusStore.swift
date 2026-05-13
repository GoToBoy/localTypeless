import Foundation
import Observation

@MainActor
@Observable
final class ModelStatusStore {
    private var statuses: [ModelKind: ModelStatus] = [:]

    func status(for kind: ModelKind) -> ModelStatus {
        statuses[kind] ?? .notDownloaded
    }

    func set(_ status: ModelStatus, for kind: ModelKind) {
        statuses[kind] = status
    }

    func refreshDownloadedStatuses() {
        for kind in ModelKind.allCases {
            guard case .notDownloaded = status(for: kind) else { continue }
            if ModelStorage.isDownloaded(kind) {
                statuses[kind] = .downloaded
            }
        }
    }

    func isReady(_ kind: ModelKind) -> Bool {
        if case .resident = status(for: kind) { return true }
        return false
    }

    func canLoadOnDemand(_ kind: ModelKind) -> Bool {
        switch status(for: kind) {
        case .downloaded, .loading, .resident:
            return true
        case .notDownloaded, .downloading, .failed:
            return false
        }
    }
}
