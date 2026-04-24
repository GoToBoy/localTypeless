import Foundation
@preconcurrency import WhisperKit

enum WhisperKitASRError: LocalizedError {
    case modelNotReady
    case emptyAudio
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady: return String(localized: "ASR model is not loaded")
        case .emptyAudio: return String(localized: "No audio captured")
        case .transcriptionFailed(let m): return String(localized: "Transcription failed: \(m)")
        }
    }
}

/// Language mode the user can force. `nil` means auto-detect.
struct ASROptions: Sendable {
    var forcedLanguage: String?  // BCP-47 ("en", "zh") — nil = auto
    static let auto = ASROptions(forcedLanguage: nil)
}

// @unchecked Sendable: stored fields are either `let` or NSLock-protected, and collaborators
// (ASRModelManaging is an actor, AudioBuffer is lock-protected) handle their own synchronization.
final class WhisperKitASRService: ASRService, @unchecked Sendable {

    private let manager: any ASRModelManaging
    private var _options: ASROptions
    private let optionsLock = NSLock()

    var options: ASROptions {
        optionsLock.lock(); defer { optionsLock.unlock() }
        return _options
    }

    func setOptions(_ new: ASROptions) {
        optionsLock.lock(); _options = new; optionsLock.unlock()
    }

    init(manager: any ASRModelManaging, options: ASROptions = .auto) {
        self.manager = manager
        self._options = options
    }

    func transcribe(_ audio: AudioBuffer) async throws -> Transcript {
        let samples = audio.snapshot()
        guard !samples.isEmpty else { throw WhisperKitASRError.emptyAudio }

        let opts = options

        // Ensure the model is ready (idempotent if already loaded).
        try await manager.ensureReady(.asrWhisperLargeV3Turbo)
        guard let kit = await manager.whisperKit else {
            throw WhisperKitASRError.modelNotReady
        }

        do {
            let decodeOptions = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: opts.forcedLanguage,  // nil → auto-detect
                temperature: 0.0,
                usePrefillPrompt: true,
                skipSpecialTokens: true,
                withoutTimestamps: false
            )

            // audioArray: (singular) is the single-array overload returning [TranscriptionResult]
            let results: [TranscriptionResult] = try await kit.transcribe(
                audioArray: samples,
                decodeOptions: decodeOptions
            )
            let first = results.first
            let text = first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lang = first?.language ?? opts.forcedLanguage ?? "en"
            let segs: [Transcript.Segment] = (first?.segments ?? []).map {
                Transcript.Segment(
                    text: $0.text,
                    startSeconds: Double($0.start),
                    endSeconds: Double($0.end)
                )
            }
            return Transcript(text: text, language: lang, segments: segs)
        } catch {
            throw WhisperKitASRError.transcriptionFailed(error.localizedDescription)
        }
    }
}
