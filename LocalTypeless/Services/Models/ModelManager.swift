import Foundation

/// Shared lifecycle operations every model manager must implement.
protocol ModelLifecycle: Actor {
    /// Ensure the given model files are present on disk. This must not load the
    /// model into RAM.
    func ensureDownloaded(_ kind: ModelKind) async throws

    /// Ensure the given model is downloaded AND loaded in RAM.
    /// Publishes progress via the injected store.
    func ensureReady(_ kind: ModelKind) async throws

    /// Release the model from RAM (if loaded). Files on disk are retained.
    func unload(_ kind: ModelKind) async
}

/// Polish-specific manager protocol: hides LLM backend types (MLX, llama.cpp,
/// remote API, …) behind a single generation call. ASR managers don't share a
/// protocol because the WhisperKit handle is a concrete type leak — each ASR
/// service holds its concrete manager directly.
protocol PolishModelManaging: ModelLifecycle {
    /// Run a single-turn chat prompt and return the generated text.
    func generate(system: String, user: String) async throws -> String
}

enum ModelManagerError: LocalizedError {
    case unsupportedKind(ModelKind)
    case initializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedKind(let k): return "Model kind \(k.rawValue) not supported by this manager"
        case .initializationFailed(let m): return "Model initialization failed: \(m)"
        }
    }
}
