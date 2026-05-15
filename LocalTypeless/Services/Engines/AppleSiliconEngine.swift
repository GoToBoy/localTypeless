#if APPLE_SILICON_ENGINE
import Foundation

/// Apple Silicon engine: WhisperKit (Core ML + ANE) for ASR, MLX for polish.
/// Only compiled when `APPLE_SILICON_ENGINE` is defined (see `project.yml`),
/// because MLX-swift won't build for `x86_64`.
@MainActor
final class AppleSiliconEngine: DictationEngine {

    let asr: ASRService
    let polish: PolishService?

    private let asrManager: WhisperKitModelManager
    private let polishManager: MLXPolishModelManager
    private let whisperASR: WhisperKitASRService

    var requiredModelKinds: [ModelKind] {
        [.asrWhisperLargeV3Turbo, .polishQwen25_3bInstruct4bit]
    }

    init(store: ModelStatusStore) {
        let asrMgr = WhisperKitModelManager(store: store)
        let polishMgr = MLXPolishModelManager(store: store)
        let asrSvc = WhisperKitASRService(manager: asrMgr)
        self.asrManager = asrMgr
        self.polishManager = polishMgr
        self.whisperASR = asrSvc
        self.asr = asrSvc
        self.polish = MLXPolishService(manager: polishMgr)
    }

    func setASROptions(_ options: ASROptions) {
        whisperASR.setOptions(options)
    }

    func download(_ kind: ModelKind) async throws {
        switch kind {
        case .asrWhisperLargeV3Turbo:
            try await asrManager.ensureReady(kind)
        case .polishQwen25_3bInstruct4bit:
            try await polishManager.ensureReady(kind)
        case .asrWhisperCppSmall:
            // Portable engine's model; not used on Apple Silicon.
            throw ModelManagerError.unsupportedKind(kind)
        }
    }

    func unload(_ kind: ModelKind) async {
        switch kind {
        case .asrWhisperLargeV3Turbo:
            await asrManager.unload(kind)
        case .polishQwen25_3bInstruct4bit:
            await polishManager.unload(kind)
        case .asrWhisperCppSmall:
            break  // not owned by this engine
        }
    }

    func unloadAllModels() async {
        await asrManager.unload(.asrWhisperLargeV3Turbo)
        await polishManager.unload(.polishQwen25_3bInstruct4bit)
    }
}
#endif
