import XCTest
@testable import LocalTypeless

@MainActor
final class MLXPolishServiceTests: XCTestCase {

    private var shouldSkip: Bool {
        ProcessInfo.processInfo.environment["LOCAL_TYPELESS_SKIP_MODEL_TESTS"] == "1"
    }

    func test_polishes_english_transcript() async throws {
        try XCTSkipIf(shouldSkip, "Model tests disabled via env flag")

        let store = ModelStatusStore()
        let manager = MLXPolishModelManager(store: store)
        let service = MLXPolishService(manager: manager)

        let transcript = Transcript(
            text: "um so like, I was thinking, uh, we could maybe, you know, ship it tomorrow",
            language: "en",
            segments: []
        )

        let polished = try await service.polish(transcript, prompt: "")
        XCTAssertFalse(polished.isEmpty)
        XCTAssertFalse(polished.lowercased().contains("um"))
        XCTAssertFalse(polished.lowercased().contains("you know"))
    }

    func test_polishes_chinese_transcript() async throws {
        try XCTSkipIf(shouldSkip, "Model tests disabled via env flag")

        let store = ModelStatusStore()
        let manager = MLXPolishModelManager(store: store)
        let service = MLXPolishService(manager: manager)

        let transcript = Transcript(
            text: "那个 嗯 我们明天 呃 可以发布一下",
            language: "zh",
            segments: []
        )

        let polished = try await service.polish(transcript, prompt: "")
        XCTAssertFalse(polished.isEmpty)
        XCTAssertFalse(polished.contains("嗯"))
        XCTAssertFalse(polished.contains("呃"))
    }

    func test_falls_back_on_empty_input() async throws {
        try XCTSkipIf(shouldSkip, "Model tests disabled via env flag")

        let store = ModelStatusStore()
        let manager = MLXPolishModelManager(store: store)
        let service = MLXPolishService(manager: manager)

        let transcript = Transcript(text: "   ", language: "en", segments: [])
        await XCTAssertThrowsErrorAsync(
            try await service.polish(transcript, prompt: "")
        )
    }
}

// Helper for async XCTest (XCTest doesn't ship XCTAssertThrowsErrorAsync).
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected throw", file: file, line: line)
    } catch {
        // expected
    }
}
