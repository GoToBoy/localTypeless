import XCTest
@testable import LocalTypeless

/// Guards the thread-safety contract of AudioLevelMeter: the Recorder tap
/// pushes samples from Core Audio's IO thread while the SwiftUI HUD reads
/// on main. A regression here could crash the app under recording (the
/// exact state a user notices most) or show a frozen waveform.
final class AudioLevelMeterTests: XCTestCase {

    func test_beginSession_stamps_startedAt_and_zeros_history() {
        let meter = AudioLevelMeter(historySize: 8)
        XCTAssertNil(meter.startedAt)

        meter.record(samples: [0.5, 0.5, 0.5, 0.5])
        XCTAssertGreaterThan(meter.smoothedLevel, 0)

        meter.beginSession()
        XCTAssertNotNil(meter.startedAt)
        XCTAssertEqual(meter.smoothedLevel, 0, "beginSession must zero smoothed level")
        XCTAssertTrue(meter.history(count: 8).allSatisfy { $0 == 0 },
                      "beginSession must zero the ring buffer")
    }

    func test_endSession_clears_startedAt_but_preserves_history() {
        let meter = AudioLevelMeter()
        meter.beginSession()
        meter.record(samples: [0.3, 0.3, 0.3, 0.3])
        let leveledBefore = meter.smoothedLevel
        XCTAssertGreaterThan(leveledBefore, 0)

        meter.endSession()
        XCTAssertNil(meter.startedAt)
        // History is intentionally kept so the HUD's last frame doesn't
        // snap to zero mid-fade-out — the view is dismissed via state
        // transition, not by the meter.
        XCTAssertEqual(meter.smoothedLevel, leveledBefore,
                       "endSession must not disturb the smoothed level")
    }

    func test_record_increases_level_for_louder_signal() {
        let meter = AudioLevelMeter()
        meter.beginSession()

        meter.record(samples: Array(repeating: Float(0.01), count: 256))
        let quiet = meter.smoothedLevel

        // Pump several loud chunks so the attack phase of the smoother has
        // had multiple opportunities to climb.
        for _ in 0..<8 {
            meter.record(samples: Array(repeating: Float(0.5), count: 256))
        }
        let loud = meter.smoothedLevel

        XCTAssertGreaterThan(loud, quiet,
                             "loud samples must drive smoothedLevel higher than quiet samples")
        XCTAssertLessThanOrEqual(loud, 1.0, "smoothedLevel must never exceed 1.0")
    }

    func test_empty_sample_chunk_is_ignored() {
        let meter = AudioLevelMeter()
        meter.beginSession()
        meter.record(samples: [])
        XCTAssertEqual(meter.smoothedLevel, 0)
    }

    func test_history_returns_requested_count_oldest_to_newest() {
        let meter = AudioLevelMeter(historySize: 4)
        meter.beginSession()

        // Push 3 increasingly loud bursts.
        meter.record(samples: Array(repeating: Float(0.05), count: 128))
        let a = meter.smoothedLevel
        meter.record(samples: Array(repeating: Float(0.2), count: 128))
        let b = meter.smoothedLevel
        meter.record(samples: Array(repeating: Float(0.4), count: 128))
        let c = meter.smoothedLevel

        let hist = meter.history(count: 4)
        XCTAssertEqual(hist.count, 4)
        // Requested count > live entries: left-pad with zeros (oldest side).
        XCTAssertEqual(hist[0], 0, accuracy: 0.0001,
                       "requesting more than we've recorded should left-pad with zero")
        XCTAssertEqual(hist[1], a, accuracy: 0.0001)
        XCTAssertEqual(hist[2], b, accuracy: 0.0001)
        XCTAssertEqual(hist[3], c, accuracy: 0.0001)
    }

    func test_concurrent_record_and_read_does_not_crash() {
        // Smoke test for the lock: hammer from two threads for a bit. Real
        // audio feeds one chunk every ~50 ms but this exaggerates it to
        // make any lost-wakeup or torn-read issue obvious.
        let meter = AudioLevelMeter()
        meter.beginSession()
        let writerDone = expectation(description: "writer finished")
        let readerDone = expectation(description: "reader finished")

        DispatchQueue.global().async {
            for _ in 0..<2_000 {
                meter.record(samples: Array(repeating: Float.random(in: 0...0.5), count: 64))
            }
            writerDone.fulfill()
        }
        DispatchQueue.global().async {
            for _ in 0..<2_000 {
                _ = meter.smoothedLevel
                _ = meter.history(count: 32)
                _ = meter.startedAt
            }
            readerDone.fulfill()
        }
        wait(for: [writerDone, readerDone], timeout: 10)
    }
}
