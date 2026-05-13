import Foundation
import WhisperKit

actor WhisperKitModelManager: ASRModelManaging {

    private let store: ModelStatusStore
    private var kit: WhisperKit?
    private var downloadInFlight: Task<Void, Error>?
    private var inFlight: Task<Void, Error>?

    init(store: ModelStatusStore) {
        self.store = store
    }

    var whisperKit: WhisperKit? { kit }

    func ensureDownloaded(_ kind: ModelKind) async throws {
        guard kind == .asrWhisperLargeV3Turbo else {
            throw ModelManagerError.unsupportedKind(kind)
        }
        if kit != nil {
            await MainActor.run { store.set(.resident, for: kind) }
            return
        }
        if ModelStorage.isDownloaded(kind) {
            await MainActor.run { store.set(.downloaded, for: kind) }
            return
        }
        if let existing = downloadInFlight {
            try await existing.value
            return
        }

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.download(kind: kind)
        }
        downloadInFlight = task
        defer { downloadInFlight = nil }
        try await task.value
    }

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

        if let existing = downloadInFlight {
            try await existing.value
        }

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.load(kind: kind)
        }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    private func download(kind: ModelKind) async throws {
        await MainActor.run { store.set(.downloading(progress: 0), for: kind) }
        do {
            _ = try await WhisperKit.download(
                variant: ModelStorage.whisperModelVariant,
                downloadBase: try ModelStorage.modelsDirectory(),
                from: ModelStorage.whisperModelRepo
            )
            await MainActor.run { store.set(.downloaded, for: kind) }
        } catch {
            await MainActor.run {
                store.set(.failed(message: error.localizedDescription), for: kind)
            }
            throw ModelManagerError.initializationFailed(error.localizedDescription)
        }
    }

    private func load(kind: ModelKind) async throws {
        try await ensureDownloaded(kind)
        guard let modelFolder = ModelStorage.downloadedModelDirectory(kind) else {
            throw ModelManagerError.initializationFailed("Model files are not downloaded")
        }
        await MainActor.run { store.set(.loading, for: kind) }
        do {
            let config = WhisperKitConfig(
                downloadBase: try ModelStorage.modelsDirectory(),
                modelFolder: modelFolder.path,
                verbose: false,
                logLevel: .info,
                prewarm: true,
                load: true,
                download: false
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
