import Foundation
import WhisperKit

/// Shared lifecycle operations every model manager must implement.
protocol ModelLifecycle: Actor {
    /// Ensure the given model is downloaded AND loaded in RAM.
    /// Publishes progress via the injected store.
    func ensureReady(_ kind: ModelKind) async throws

    /// Release the model from RAM (if loaded). Files on disk are retained.
    func unload(_ kind: ModelKind) async
}

/// ASR-specific manager protocol: exposes the underlying WhisperKit instance.
protocol ASRModelManaging: ModelLifecycle {
    /// nil until ensureReady succeeds.
    var whisperKit: WhisperKit? { get async }
}

/// Polish-specific manager protocol: hides MLX types behind a generation call.
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
