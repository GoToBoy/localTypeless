import XCTest
@preconcurrency import AVFoundation
@testable import LocalTypeless

/// Exercises `Recorder.start() -> stop()` against the real AVAudioEngine so
/// regressions in the crash-prevention path (NSException shim + tap cleanup
/// + HAL pre-flight) surface as test failures rather than app-level SIGABRT.
///
/// These tests are gated: when the host has no usable default input device
/// (CI, headless runners, misconfigured workstation), the real capture
/// paths are skipped with `XCTSkip` so the suite stays green. The error
/// paths still run on every host.
@MainActor
final class RecorderLifecycleTests: XCTestCase {

    // MARK: - Helpers

    private func makeRecorder() -> (Recorder, LocalTypeless.AudioBuffer, AudioLevelMeter) {
        let buffer = LocalTypeless.AudioBuffer(maxSeconds: 10, sampleRate: 16_000)
        let meter = AudioLevelMeter()
        let recorder = Recorder(buffer: buffer, meter: meter)
        return (recorder, buffer, meter)
    }

    private func skipIfNoInputDevice() throws {
        if !Recorder.defaultInputDeviceHasInputStreams() {
            throw XCTSkip("no default input device configured on this host — skipping real-capture test")
        }
    }

    // MARK: - Pre-flight (runs on all hosts)

    func test_defaultInputDeviceHasInputStreams_returnsBool() {
        // We can't know the host's mic configuration for sure, but the call
        // must not crash and must return a Bool. Guards the Core Audio
        // property-get code path against bitrot on SDK updates.
        let result = Recorder.defaultInputDeviceHasInputStreams()
        XCTAssertTrue(result == true || result == false)
    }

    func test_hasUsableRecordingHardware_returnsBool() {
        let result = Recorder.hasUsableRecordingHardware()
        XCTAssertTrue(result == true || result == false)
    }

    // MARK: - Error paths (runs on all hosts)

    func test_recorderError_installTapFailed_hasLocalizedDescription() {
        let err = Recorder.RecorderError.installTapFailed
        XCTAssertNotNil(err.errorDescription)
    }

    func test_recorderError_inputDeviceNotReady_hasLocalizedDescription() {
        let err = Recorder.RecorderError.inputDeviceNotReady
        XCTAssertNotNil(err.errorDescription)
    }

    // MARK: - SafeAudioTap shim (runs on all hosts)

    /// Builds a standalone engine (not attached to a device via start()) and
    /// asks SafeAudioTap to install a tap with a deliberately incompatible
    /// format. On affected builds this used to SIGABRT the process because
    /// AVAudioEngine raises an NSException that Swift's `try` can't catch.
    /// After the shim lands, the NSException becomes a throwable NSError.
    func test_safeAudioTap_convertsNSException_intoThrownError() throws {
        let engine = AVAudioEngine()
        _ = engine.inputNode  // touch to materialize
        // Incompatible format: the input node has its own live hardware
        // format. Asking for a completely different layout triggers the
        // internal assertion path.
        let mismatched = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 8_000,
            channels: 2,
            interleaved: true
        )!
        // The call must either succeed (some hosts accept it) or throw —
        // the hard requirement is that it never aborts the process.
        do {
            try SafeAudioTap.installTap(
                on: engine.inputNode,
                bus: 0,
                bufferSize: 1024,
                format: mismatched,
                block: { _, _ in }
            )
            engine.inputNode.removeTap(onBus: 0)  // clean up if we got lucky
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    // MARK: - Happy-path lifecycle (skipped without input device)

    func test_startThenStop_cleanCycle() throws {
        try skipIfNoInputDevice()
        let (recorder, buffer, meter) = makeRecorder()

        try recorder.start()
        XCTAssertNotNil(meter.startedAt, "meter session should begin on start()")

        // Give the audio unit a moment to push at least one buffer so the
        // tap path is genuinely exercised, not just wired.
        let exp = expectation(description: "first audio buffer")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        recorder.stop()
        XCTAssertNil(meter.startedAt, "meter session should end on stop()")
        // Buffer may or may not contain samples depending on how fast the
        // HAL ramps, so we don't assert on count — we only assert the
        // lifecycle didn't crash and state is coherent.
        _ = buffer.durationSeconds
    }

    func test_doubleStart_isIdempotent() throws {
        try skipIfNoInputDevice()
        let (recorder, _, meter) = makeRecorder()

        try recorder.start()
        let firstStartedAt = meter.startedAt
        // Second start while running must be a no-op (guarded by
        // `isRunning`), not a re-install-tap path that would blow up on
        // `nullptr == Tap()`.
        try recorder.start()
        XCTAssertEqual(meter.startedAt, firstStartedAt, "second start must not reset the session")

        recorder.stop()
    }

    func test_doubleStop_isIdempotent() throws {
        try skipIfNoInputDevice()
        let (recorder, _, _) = makeRecorder()

        try recorder.start()
        recorder.stop()
        // Second stop with nothing running must not touch the engine again
        // (the `isRunning` guard protects `engine.inputNode.removeTap`).
        recorder.stop()
    }

    func test_stopWithoutStart_isNoOp() throws {
        let (recorder, _, meter) = makeRecorder()
        recorder.stop()
        XCTAssertNil(meter.startedAt)
    }

    /// The product-level invariant we actually care about: `start()` must
    /// never SIGABRT the process, regardless of what the host's default
    /// input device is doing. It may succeed, it may throw a recoverable
    /// `RecorderError`, or — on headless CI hosts — `engine.start()` may
    /// fail and propagate a non-recorder error. All three are acceptable;
    /// an uncaught NSException tearing down the process is not.
    ///
    /// We previously had a stricter "must throw a specific case" test here
    /// keyed off a Core Audio probe, but that probe turned out to be an
    /// unreliable signal on healthy machines (virtual audio devices, BT
    /// codecs, TCC sandboxing can all return 0 streams for a working mic).
    /// The real defenses are the live-format pre-flight and SafeAudioTap;
    /// this test just pins the "no SIGABRT" promise.
    func test_start_neverSigabrts_regardlessOfHost() {
        let (recorder, _, meter) = makeRecorder()
        do {
            try recorder.start()
            recorder.stop()
        } catch {
            // Any thrown error is fine — the point is we didn't abort.
            _ = error.localizedDescription
        }
        XCTAssertNil(meter.startedAt, "meter session must be torn down after stop/failure")
    }

    func test_startStopStart_reinstallsCleanly() throws {
        try skipIfNoInputDevice()
        let (recorder, _, meter) = makeRecorder()

        try recorder.start()
        recorder.stop()

        // The main crash mode before the fix: second start() after a
        // completed stop() would hit `required condition is false:
        // nullptr == Tap()` because AVAudioEngine kept the tap object
        // attached to the node. The defensive `removeTap(onBus: 0)` at
        // the top of start() is what keeps this from crashing.
        try recorder.start()
        XCTAssertNotNil(meter.startedAt)
        recorder.stop()
    }
}
