#if !APPLE_SILICON_ENGINE
import Foundation
@preconcurrency import SwiftWhisper

enum WhisperCppASRError: LocalizedError {
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

// @unchecked Sendable: stored fields are either `let` or NSLock-protected, and
// the underlying SwiftWhisper.Whisper class serialises its own state internally
// (a `whisper_full` call sets `inProgress = true` for the duration).
final class WhisperCppASRService: ASRService, @unchecked Sendable {

    private let manager: WhisperCppModelManager
    private var _options: ASROptions
    private let optionsLock = NSLock()

    var options: ASROptions {
        optionsLock.lock(); defer { optionsLock.unlock() }
        return _options
    }

    func setOptions(_ new: ASROptions) {
        optionsLock.lock(); _options = new; optionsLock.unlock()
    }

    init(manager: WhisperCppModelManager, options: ASROptions = .auto) {
        self.manager = manager
        self._options = options
    }

    func transcribe(_ audio: AudioBuffer) async throws -> Transcript {
        let samples = audio.snapshot()
        guard !samples.isEmpty else { throw WhisperCppASRError.emptyAudio }

        let opts = options

        try await manager.ensureReady(.asrWhisperCppSmall)
        guard let whisper = await manager.whisperInstance else {
            throw WhisperCppASRError.modelNotReady
        }

        // SwiftWhisper exposes language via `params.language` (WhisperLanguage),
        // which is a forced setting — there's no async hook for `whisper_full_lang_id`.
        // For auto-detect we leave the param at `.auto`; for forced modes we set
        // it explicitly.  The returned Transcript.language mirrors what we
        // requested (or "en" when auto, since SwiftWhisper doesn't surface the
        // detected id post-decode).
        let forced = opts.forcedLanguage.flatMap(WhisperLanguage.init(rawValue:))
        whisper.params.language = forced ?? .auto

        do {
            let segments = try await whisper.transcribe(audioFrames: samples)
            let text = segments
                .map { $0.text }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let mappedSegments: [Transcript.Segment] = segments.map {
                // SwiftWhisper times are in milliseconds.
                Transcript.Segment(
                    text: $0.text,
                    startSeconds: Double($0.startTime) / 1000.0,
                    endSeconds: Double($0.endTime) / 1000.0
                )
            }
            let lang = opts.forcedLanguage ?? "en"
            return Transcript(text: text, language: lang, segments: mappedSegments)
        } catch {
            throw WhisperCppASRError.transcriptionFailed(error.localizedDescription)
        }
    }
}
#endif
