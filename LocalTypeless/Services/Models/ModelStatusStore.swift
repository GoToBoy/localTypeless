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

    func isReady(_ kind: ModelKind) -> Bool {
        if case .resident = status(for: kind) { return true }
        return false
    }
}
