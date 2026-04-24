import XCTest
@testable import LocalTypeless

final class StubASRServiceTests: XCTestCase {

    func test_returnsFixedTranscriptWithProvidedLanguage() async throws {
        let svc = StubASRService(fixedText: "hello world", language: "en")
        let buf = AudioBuffer(maxSeconds: 1, sampleRate: 16_000)
        buf.append(Array(repeating: Float(0), count: 16_000))
        let t = try await svc.transcribe(buf)
        XCTAssertEqual(t.text, "hello world")
        XCTAssertEqual(t.language, "en")
    }

    func test_includesFullTextAsSingleSegment() async throws {
        let svc = StubASRService(fixedText: "你好，世界", language: "zh")
        let buf = AudioBuffer(maxSeconds: 1, sampleRate: 16_000)
        let t = try await svc.transcribe(buf)
        XCTAssertEqual(t.segments.count, 1)
        XCTAssertEqual(t.segments.first?.text, "你好，世界")
    }
}
