import Foundation

enum EngineModelRole: Sendable, Equatable {
    case speech
    case polish
}

struct EngineModelSlot: Sendable, Equatable {
    let role: EngineModelRole
    let kind: ModelKind
}

/// Bundles the platform-specific implementations of ASR, polish, and model
/// lifecycle into a single object so `AppDelegate` doesn't need to know which
/// concrete services are in use.
///
/// One engine is selected at startup by `EngineFactory.make(store:)` — either
/// `AppleSiliconEngine` (WhisperKit + MLX) on `APPLE_SILICON_ENGINE` builds,
/// or `PortableEngine` (cross-platform, no LLM polish) otherwise.
@MainActor
protocol DictationEngine: AnyObject {
    var asr: ASRService { get }

    /// `nil` means this engine ships without an LLM polish step. The pipeline
    /// will inject the raw transcript instead.
    var polish: PolishService? { get }

    /// Models that must reach `.resident` before dictation can run.
    /// `AppDelegate.ensureModelsReady()` iterates this list.
    var requiredModelKinds: [ModelKind] { get }

    /// Role-oriented model list for UI and policy surfaces. Concrete engines
    /// own the mapping from product roles (speech / polish) to backend model
    /// files so UI code doesn't branch on platform-specific `ModelKind` cases.
    var modelSlots: [EngineModelSlot] { get }

    /// Forwards an ASR-options change (e.g. forced language) to whatever
    /// concrete ASR service this engine wraps. No-op for engines whose ASR
    /// doesn't support runtime options.
    func setASROptions(_ options: ASROptions)

    /// Triggers download + load for `kind`. Used by the model-download UI.
    /// Throws `ModelManagerError.unsupportedKind` if `kind` isn't one of this
    /// engine's `requiredModelKinds`.
    func download(_ kind: ModelKind) async throws

    /// Releases `kind` from RAM (file on disk is retained). Used by
    /// `MemoryAdvisor`-driven unloads when polish should be skipped under
    /// memory pressure, and as a no-op for kinds this engine doesn't own.
    func unload(_ kind: ModelKind) async

    /// Releases every loaded model from RAM. Files on disk are retained.
    func unloadAllModels() async
}

extension DictationEngine {
    var requiredModelKinds: [ModelKind] {
        modelSlots.map(\.kind)
    }

    var speechModelKind: ModelKind? {
        modelSlots.first { $0.role == .speech }?.kind
    }
}
