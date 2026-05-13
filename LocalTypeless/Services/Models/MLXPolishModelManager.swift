import Foundation
import Hub
import MLXLLM
import MLXLMCommon

actor MLXPolishModelManager: PolishModelManaging {

    private let store: ModelStatusStore
    private var container: ModelContainer?
    private var downloadInFlight: Task<Void, Error>?
    private var inFlight: Task<Void, Error>?

    init(store: ModelStatusStore) {
        self.store = store
    }

    func ensureDownloaded(_ kind: ModelKind) async throws {
        guard kind == .polishQwen25_3bInstruct4bit else {
            throw ModelManagerError.unsupportedKind(kind)
        }
        if container != nil {
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
        guard kind == .polishQwen25_3bInstruct4bit else {
            throw ModelManagerError.unsupportedKind(kind)
        }
        if container != nil {
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
            let hub = HubApi(downloadBase: try ModelStorage.modelsDirectory())
            let config = ModelConfiguration(id: ModelStorage.mlxPolishModelId)
            _ = try await downloadModel(hub: hub, configuration: config) { _ in }
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
        guard let modelDirectory = ModelStorage.downloadedModelDirectory(kind) else {
            throw ModelManagerError.initializationFailed("Model files are not downloaded")
        }
        await MainActor.run { store.set(.loading, for: kind) }
        do {
            let hub = HubApi(downloadBase: try ModelStorage.modelsDirectory())
            let config = ModelConfiguration(directory: modelDirectory)
            let c = try await LLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: config
            )
            self.container = c
            await MainActor.run { store.set(.resident, for: kind) }
        } catch {
            await MainActor.run {
                store.set(.failed(message: error.localizedDescription), for: kind)
            }
            throw ModelManagerError.initializationFailed(error.localizedDescription)
        }
    }

    func unload(_ kind: ModelKind) async {
        guard kind == .polishQwen25_3bInstruct4bit else { return }
        container = nil
        await MainActor.run { store.set(.downloaded, for: kind) }
    }

    /// Runs a single-turn chat prompt against the loaded MLX model container.
    func generate(system: String, user: String) async throws -> String {
        guard let container else {
            throw ModelManagerError.initializationFailed("Model container not loaded")
        }
        let result: String = try await container.perform { context in
            let chat: [Chat.Message] = [
                .system(system),
                .user(user),
            ]
            let userInput = UserInput(chat: chat)
            let lmInput = try await context.processor.prepare(input: userInput)
            // Rough estimate: 1 token ≈ 2 chars for Qwen tokenizer with CJK mix.
            let approxInputTokens = max(user.count / 2, 16)
            let maxOutputTokens = approxInputTokens * 2
            let params = GenerateParameters(
                maxTokens: maxOutputTokens,
                temperature: 0.2
            )
            // Use the ([Int]) -> GenerateDisposition overload which returns GenerateResult with .output.
            let generateResult: GenerateResult = try MLXLMCommon.generate(
                input: lmInput,
                parameters: params,
                context: context
            ) { (_: [Int]) in
                GenerateDisposition.more
            }
            return generateResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
