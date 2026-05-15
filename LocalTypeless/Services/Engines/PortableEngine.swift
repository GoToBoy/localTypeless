#if !APPLE_SILICON_ENGINE
import Foundation

/// Cross-platform engine: ASR via `whisper.cpp` (through SwiftWhisper),
/// no LLM polish. Targets Intel Macs and other hosts where MLX won't run.
///
/// Only compiled when `APPLE_SILICON_ENGINE` is _not_ defined (see
/// `project.portable.yml`), because the Apple Silicon build doesn't link
/// SwiftWhisper.
@MainActor
final class PortableEngine: DictationEngine {

    let asr: ASRService
    let polish: PolishService? = nil

    private let modelManager: WhisperCppModelManager
    private let whisperASR: WhisperCppASRService

    var modelSlots: [EngineModelSlot] {
        [EngineModelSlot(role: .speech, kind: .asrWhisperCppSmall)]
    }

    init(store: ModelStatusStore) {
        let mgr = WhisperCppModelManager(store: store)
        let svc = WhisperCppASRService(manager: mgr)
        self.modelManager = mgr
        self.whisperASR = svc
        self.asr = svc
    }

    func setASROptions(_ options: ASROptions) {
        whisperASR.setOptions(options)
    }

    func download(_ kind: ModelKind) async throws {
        switch kind {
        case .asrWhisperCppSmall:
            try await modelManager.ensureReady(kind)
        default:
            throw ModelManagerError.unsupportedKind(kind)
        }
    }

    func unload(_ kind: ModelKind) async {
        switch kind {
        case .asrWhisperCppSmall:
            await modelManager.unload(kind)
        default:
            break  // not owned by this engine
        }
    }

    func unloadAllModels() async {
        await modelManager.unload(.asrWhisperCppSmall)
    }
}
#endif
