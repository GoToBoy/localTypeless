import XCTest
@testable import LocalTypeless

final class StubPolishServiceTests: XCTestCase {

    func test_capitalizesAndAddsPeriod() async throws {
        let svc = StubPolishService()
        let t = Transcript(text: "hello world", language: "en", segments: [])
        let polished = try await svc.polish(t, prompt: "")
        XCTAssertEqual(polished, "Hello world.")
    }

    func test_preservesChineseUntouched() async throws {
        let svc = StubPolishService()
        let t = Transcript(text: "你好，世界", language: "zh", segments: [])
        let polished = try await svc.polish(t, prompt: "")
        XCTAssertEqual(polished, "你好，世界")
    }

    func test_removesTrivialFillerWordsEnglish() async throws {
        let svc = StubPolishService()
        let t = Transcript(text: "um hello uh world", language: "en", segments: [])
        let polished = try await svc.polish(t, prompt: "")
        XCTAssertEqual(polished, "Hello world.")
    }
}
