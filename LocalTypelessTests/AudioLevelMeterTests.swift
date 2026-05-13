import XCTest
@testable import LocalTypeless

final class AudioLevelMeterTests: XCTestCase {
    func test_beginSession_stampsStartedAtAndZerosHistory() {
        let meter = AudioLevelMeter(historySize: 8)
        XCTAssertNil(meter.startedAt)

        meter.record(samples: [0.5, 0.5, 0.5, 0.5])
        XCTAssertGreaterThan(meter.smoothedLevel, 0)

        meter.beginSession()

        XCTAssertNotNil(meter.startedAt)
        XCTAssertEqual(meter.smoothedLevel, 0)
        XCTAssertFalse(meter.isVoiceActive)
        XCTAssertFalse(meter.hasMeaningfulSpeech)
        XCTAssertTrue(meter.history(count: 8).allSatisfy { $0 == 0 })
    }

    func test_recordIncreasesLevelForLouderSignal() {
        let meter = AudioLevelMeter()
        meter.beginSession()

        meter.record(samples: Array(repeating: Float(0.01), count: 256))
        let quiet = meter.smoothedLevel
        for _ in 0..<8 {
            meter.record(samples: Array(repeating: Float(0.5), count: 256))
        }

        XCTAssertGreaterThan(meter.smoothedLevel, quiet)
        XCTAssertLessThanOrEqual(meter.smoothedLevel, 1)
    }

    func test_noiseBelowThresholdStaysInactive() {
        let meter = AudioLevelMeter(historySize: 4, silenceThreshold: 0.02)
        meter.beginSession()

        for _ in 0..<4 {
            meter.record(samples: Array(repeating: Float(0.005), count: 128))
        }

        XCTAssertFalse(meter.isVoiceActive)
        XCTAssertFalse(meter.hasMeaningfulSpeech)
        XCTAssertEqual(meter.smoothedLevel, 0, accuracy: 0.0001)
        XCTAssertTrue(meter.history(count: 4).allSatisfy { $0 == 0 })
    }

    func test_singleSpikeDoesNotCountAsMeaningfulSpeech() {
        let meter = AudioLevelMeter(historySize: 4, silenceThreshold: 0.02, minimumSpeechFrames: 3)
        meter.beginSession()

        meter.record(samples: Array(repeating: Float(0.25), count: 128))
        meter.record(samples: Array(repeating: Float(0), count: 128))
        meter.record(samples: Array(repeating: Float(0), count: 128))

        XCTAssertFalse(meter.hasMeaningfulSpeech)
    }

    func test_repeatedVoiceFramesCountAsMeaningfulSpeech() {
        let meter = AudioLevelMeter(historySize: 4, silenceThreshold: 0.02, minimumSpeechFrames: 3)
        meter.beginSession()

        for _ in 0..<3 {
            meter.record(samples: Array(repeating: Float(0.25), count: 128))
        }

        XCTAssertTrue(meter.hasMeaningfulSpeech)
    }

    func test_voiceActivityReleasesAfterHeldSilentFrames() {
        let meter = AudioLevelMeter(historySize: 6, silenceThreshold: 0.02, activeHoldFrames: 2)
        meter.beginSession()

        meter.record(samples: Array(repeating: Float(0.2), count: 128))
        XCTAssertTrue(meter.isVoiceActive)

        meter.record(samples: Array(repeating: Float(0), count: 128))
        XCTAssertTrue(meter.isVoiceActive)

        meter.record(samples: Array(repeating: Float(0), count: 128))
        XCTAssertFalse(meter.isVoiceActive)
    }

    func test_historyReturnsRequestedCountOldestToNewest() {
        let meter = AudioLevelMeter(historySize: 4)
        meter.beginSession()

        meter.record(samples: Array(repeating: Float(0.05), count: 128))
        let first = meter.smoothedLevel
        meter.record(samples: Array(repeating: Float(0.2), count: 128))
        let second = meter.smoothedLevel
        meter.record(samples: Array(repeating: Float(0.4), count: 128))
        let third = meter.smoothedLevel

        let history = meter.history(count: 4)
        XCTAssertEqual(history[0], 0, accuracy: 0.0001)
        XCTAssertEqual(history[1], first, accuracy: 0.0001)
        XCTAssertEqual(history[2], second, accuracy: 0.0001)
        XCTAssertEqual(history[3], third, accuracy: 0.0001)
    }
}
