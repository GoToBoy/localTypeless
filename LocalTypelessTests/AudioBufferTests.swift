import XCTest
@testable import LocalTypeless

final class AudioBufferTests: XCTestCase {

    func test_newBufferIsEmpty() {
        let b = AudioBuffer(maxSeconds: 120, sampleRate: 16_000)
        XCTAssertEqual(b.sampleCount, 0)
        XCTAssertEqual(b.durationSeconds, 0)
    }

    func test_appendIncreasesCount() {
        let b = AudioBuffer(maxSeconds: 120, sampleRate: 16_000)
        b.append([0.0, 0.1, 0.2, 0.3])
        XCTAssertEqual(b.sampleCount, 4)
    }

    func test_durationMatchesSampleRate() {
        let b = AudioBuffer(maxSeconds: 120, sampleRate: 16_000)
        b.append(Array(repeating: 0, count: 16_000))
        XCTAssertEqual(b.durationSeconds, 1.0, accuracy: 0.001)
    }

    func test_dropsOldestSamplesWhenExceedingMax() {
        let b = AudioBuffer(maxSeconds: 1, sampleRate: 16_000)
        b.append(Array(repeating: Float(1), count: 16_000))
        b.append(Array(repeating: Float(2), count: 8_000))
        XCTAssertEqual(b.sampleCount, 16_000)
        let snapshot = b.snapshot()
        XCTAssertEqual(snapshot.first, 1)
        XCTAssertEqual(snapshot.last, 2)
    }

    func test_resetEmptiesBuffer() {
        let b = AudioBuffer(maxSeconds: 1, sampleRate: 16_000)
        b.append([1, 2, 3])
        b.reset()
        XCTAssertEqual(b.sampleCount, 0)
    }
}
