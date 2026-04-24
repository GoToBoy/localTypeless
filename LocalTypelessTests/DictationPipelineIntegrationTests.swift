import XCTest
@testable import LocalTypeless

/// End-to-end verification of the "hotkey pressed → transcript written to
/// history" product flow, wired together in the same shape `AppDelegate`
/// uses at runtime:
///
///   AudioBuffer  ─▶  ASRService  ─▶  PolishService  ─▶  (History insert)
///                        │                │
///                     StateMachine advances through each phase
///
/// This test doesn't boot AVAudioEngine — that path is covered by
/// `RecorderLifecycleTests`. Here we inject fake audio samples straight
/// into the buffer so the pipeline runs deterministically on every host,
/// including CI.
@MainActor
final class DictationPipelineIntegrationTests: XCTestCase {

    // MARK: - Fake audio

    /// Fills the buffer with ~1s of low-amplitude noise so the meter has
    /// something to report and the ASR stub has something to return a
    /// transcript from. Not real speech — the stubs don't need it.
    private func fillWithFakeSamples(_ buffer: LocalTypeless.AudioBuffer) {
        var samples: [Float] = []
        samples.reserveCapacity(16_000)
        for i in 0..<16_000 {
            samples.append(Float(sin(Double(i) * 0.01)) * 0.05)
        }
        buffer.append(samples)
    }

    // MARK: - End-to-end

    func test_stubPipeline_producesPolishedTranscript_andAdvancesThroughAllStates() async throws {
        let buffer = AudioBuffer(maxSeconds: 10, sampleRate: 16_000)
        let meter = AudioLevelMeter()
        let sm = StateMachine()
        let asr: ASRService = StubASRService(fixedText: "um this is a hello test", language: "en")
        let polish: PolishService = StubPolishService()

        // ─── Phase: idle → recording ───
        XCTAssertEqual(sm.state, .idle)
        sm.toggle()
        XCTAssertEqual(sm.state, .recording)
        meter.beginSession()

        // ─── Simulate capture ───
        fillWithFakeSamples(buffer)
        XCTAssertGreaterThan(buffer.sampleCount, 0)
        // Meter should have a non-nil startedAt during capture.
        XCTAssertNotNil(meter.startedAt)

        // ─── Phase: recording → transcribing ───
        sm.toggle()
        XCTAssertEqual(sm.state, .transcribing)
        meter.endSession()
        XCTAssertNil(meter.startedAt)

        let transcript = try await asr.transcribe(buffer)
        XCTAssertEqual(transcript.text, "um this is a hello test")
        XCTAssertEqual(transcript.language, "en")

        // ─── Phase: transcribing → polishing ───
        sm.advance()
        XCTAssertEqual(sm.state, .polishing)

        let polished = try await polish.polish(transcript, prompt: "")
        // StubPolishService strips English fillers (um/uh/like/…) and
        // capitalizes / terminates with a period.
        XCTAssertTrue(polished.hasSuffix(".") || polished.hasSuffix("?") || polished.hasSuffix("!"))
        XCTAssertFalse(polished.lowercased().split(separator: " ").contains("um"),
                       "polish should strip 'um' fillers")

        // ─── Phase: polishing → injecting → idle ───
        sm.advance()
        XCTAssertEqual(sm.state, .injecting)
        sm.advance()
        XCTAssertEqual(sm.state, .idle)
    }

    func test_pipelineHandles_asrTimeout_byMovingToErrorState() async throws {
        let sm = StateMachine()
        let buffer = AudioBuffer(maxSeconds: 1, sampleRate: 16_000)
        fillWithFakeSamples(buffer)
        sm.toggle()  // idle -> recording
        sm.toggle()  // recording -> transcribing

        // A fake ASR that sleeps longer than the timeout.
        let slowASR = SlowStubASR(delaySeconds: 0.5)

        do {
            _ = try await withTimeout(0.1) {
                try await slowASR.transcribe(buffer)
            }
            XCTFail("expected timeout")
        } catch PipelineTimeoutError.timedOut {
            sm.fail(message: "Transcription timed out")
            if case .error(let msg) = sm.state {
                XCTAssertEqual(msg, "Transcription timed out")
            } else {
                XCTFail("state machine should be in error state, got \(sm.state)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_pipeline_recoversFromError_backToIdle() async {
        let sm = StateMachine()
        sm.toggle(); sm.toggle()  // idle → recording → transcribing
        sm.fail(message: "ASR boom")
        XCTAssertEqual(sm.state, .error("ASR boom"))
        sm.toggle()  // error → idle
        XCTAssertEqual(sm.state, .idle)
        // User can start a fresh dictation after the error.
        sm.toggle()
        XCTAssertEqual(sm.state, .recording)
    }

    func test_emptyBuffer_stillFlowsThroughPipeline_withoutCrashing() async throws {
        let buffer = AudioBuffer(maxSeconds: 10, sampleRate: 16_000)
        let asr: ASRService = StubASRService(fixedText: "", language: "en")
        let polish: PolishService = StubPolishService()

        // No fillWithFakeSamples — buffer stays empty, mirroring the
        // "user pressed hotkey then released immediately" edge case.
        let transcript = try await asr.transcribe(buffer)
        let polished = try await polish.polish(transcript, prompt: "")
        XCTAssertEqual(polished, "")  // stub returns empty for empty input
    }
}

/// Helper stub: deliberately slow, used to exercise the timeout path.
private final class SlowStubASR: ASRService, @unchecked Sendable {
    private let delay: TimeInterval
    init(delaySeconds: TimeInterval) { self.delay = delaySeconds }
    func transcribe(_ audio: LocalTypeless.AudioBuffer) async throws -> Transcript {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return Transcript(text: "", language: "en", segments: [])
    }
}
