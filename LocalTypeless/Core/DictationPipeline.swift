import Foundation

/// Event-driven pipeline that runs the end-to-end dictation flow for a single
/// utterance: transcribe → (optional) save-audio → polish → inject → persist.
///
/// The pipeline is intentionally free of `StateMachine` / UI coupling; it emits
/// `Event`s through a callback so the caller can map them to state transitions
/// and observe results for tests.
@MainActor
final class DictationPipeline {

    struct Dependencies {
        let asr: ASRService
        let polish: PolishService
        let injector: TextInjector
        let historyStore: HistoryStore?
        let audioStore: AudioStore?
    }

    struct Input {
        let audioBuffer: AudioBuffer
        let startedAt: Date
        let targetAppProcessIdentifier: pid_t?
        let targetAppBundleId: String?
        let targetAppName: String?
        let polishEnabled: Bool
        let polishPrompt: String
        let transcribeTimeout: TimeInterval
        let polishTimeout: TimeInterval
        let saveAudio: Bool
        let audioRetentionDays: Int
    }

    enum Event {
        case transcribing
        case polishing
        case injecting
        case copyFallback(String, TextInjector.InjectionError)
        case done(DictationEntry)
        case failed(String)
    }

    typealias EventHandler = @MainActor (Event) -> Void

    private let deps: Dependencies

    init(_ deps: Dependencies) {
        self.deps = deps
    }

    func run(_ input: Input, onEvent: EventHandler) async {
        onEvent(.transcribing)

        // Pull Sendable services out so the @Sendable timeout closures don't
        // have to capture the non-Sendable Dependencies struct.
        let asr = deps.asr
        let polish = deps.polish
        let audioBuffer = input.audioBuffer
        let polishPrompt = input.polishPrompt

        let transcript: Transcript
        do {
            transcript = try await withTimeout(input.transcribeTimeout) {
                try await asr.transcribe(audioBuffer)
            }
        } catch PipelineTimeoutError.timedOut {
            onEvent(.failed("Transcription timed out"))
            return
        } catch {
            Log.asr.error("transcribe failed: \(String(describing: error), privacy: .public)")
            onEvent(.failed("ASR failed"))
            return
        }

        if input.saveAudio, let store = deps.audioStore {
            let samples = input.audioBuffer.snapshot()
            do {
                try store.save(samples: samples, sampleRate: 16_000)
                try store.pruneOlderThan(days: input.audioRetentionDays)
            } catch {
                Log.state.error("audio save failed: \(String(describing: error), privacy: .public)")
            }
        }

        let polished: String
        if input.polishEnabled {
            onEvent(.polishing)
            do {
                let generated = try await withTimeout(input.polishTimeout) {
                    try await polish.polish(transcript, prompt: polishPrompt)
                }
                polished = TranscriptTextNormalizer.finalOutput(generated, transcript: transcript)
            } catch {
                Log.polish.error("polish failed — using raw transcript")
                polished = TranscriptTextNormalizer.unpolishedOutput(for: transcript)
            }
        } else {
            polished = TranscriptTextNormalizer.unpolishedOutput(for: transcript)
        }

        onEvent(.injecting)
        do {
            try await deps.injector.inject(
                polished,
                target: .init(
                    processIdentifier: input.targetAppProcessIdentifier,
                    bundleIdentifier: input.targetAppBundleId
                )
            )
        } catch let error as TextInjector.InjectionError {
            logInjectionFallback(error)
            onEvent(.copyFallback(polished, error))
        } catch {
            Log.injector.error("injection failed: \(String(describing: error), privacy: .public)")
            onEvent(.copyFallback(polished, .pasteFailed(String(describing: error))))
        }

        let durationMs = Int(Date().timeIntervalSince(input.startedAt) * 1_000)
        let entry = DictationEntry(
            startedAt: input.startedAt,
            durationMs: durationMs,
            rawTranscript: transcript.text,
            polishedText: polished,
            language: transcript.language,
            targetAppBundleId: input.targetAppBundleId,
            targetAppName: input.targetAppName
        )
        if let store = deps.historyStore {
            _ = try? store.insert(entry)
        }

        onEvent(.done(entry))
    }

    private func logInjectionFallback(_ error: TextInjector.InjectionError) {
        switch error {
        case .accessibilityDenied:
            Log.injector.warning("accessibility denied; polished text left on pasteboard")
        case .noFocusedWindow:
            Log.injector.warning("no focused window; polished text left on pasteboard")
        case .eventCreationFailed:
            Log.injector.error("failed to create paste keyboard events; polished text left on pasteboard")
        case .appleScriptFailed(let message):
            Log.injector.error("applescript injection failed: \(message, privacy: .public)")
        case .pasteFailed(let message):
            Log.injector.error("paste injection failed: \(message, privacy: .public)")
        }
    }
}
