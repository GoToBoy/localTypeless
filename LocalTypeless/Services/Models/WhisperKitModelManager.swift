import Foundation
import WhisperKit

actor WhisperKitModelManager: ASRModelManaging {

    private let store: ModelStatusStore
    private var kit: WhisperKit?
    private var inFlight: Task<Void, Error>?
    private let modelVariant = "openai_whisper-large-v3-turbo"

    init(store: ModelStatusStore) {
        self.store = store
    }

    var whisperKit: WhisperKit? { kit }

    func ensureReady(_ kind: ModelKind) async throws {
        guard kind == .asrWhisperLargeV3Turbo else {
            throw ModelManagerError.unsupportedKind(kind)
        }
        if kit != nil {
            await MainActor.run { store.set(.resident, for: kind) }
            return
        }
        if let existing = inFlight {
            try await existing.value
            return
        }

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.load(kind: kind)
        }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    private func load(kind: ModelKind) async throws {
        await MainActor.run { store.set(.loading, for: kind) }
        do {
            // WhisperKit's default init downloads and loads the model.
            // Progress is coarse (notDownloaded → loading → resident); the ProgressReporter
            // path from WhisperKit.download(variant:from:progressCallback:) would give
            // per-byte updates but isn't wired yet — acceptable for v1.
            let config = WhisperKitConfig(
                model: modelVariant,
                modelRepo: "argmaxinc/whisperkit-coreml",
                verbose: false,
                logLevel: .info,
                prewarm: true,
                load: true,
                download: true
            )
            let wk = try await WhisperKit(config)
            self.kit = wk
            await MainActor.run { store.set(.resident, for: kind) }
        } catch {
            await MainActor.run {
                store.set(.failed(message: error.localizedDescription), for: kind)
            }
            throw ModelManagerError.initializationFailed(error.localizedDescription)
        }
    }

    func unload(_ kind: ModelKind) async {
        guard kind == .asrWhisperLargeV3Turbo else { return }
        kit = nil
        await MainActor.run { store.set(.downloaded, for: kind) }
    }
}
