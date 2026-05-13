import XCTest
@testable import LocalTypeless

final class TranscriptLanguageTests: XCTestCase {

    func test_normalized_prefersChineseTextOverMissingOrEnglishReport() {
        XCTAssertEqual(
            TranscriptLanguage.normalized(reported: nil, text: "这是一个中文口述测试"),
            "zh"
        )
        XCTAssertEqual(
            TranscriptLanguage.normalized(reported: "en", text: "我想测试一下历史记录"),
            "zh"
        )
    }

    func test_normalized_canonicalizesKnownLanguageNames() {
        XCTAssertEqual(TranscriptLanguage.normalized(reported: "zh-Hans", text: ""), "zh")
        XCTAssertEqual(TranscriptLanguage.normalized(reported: "english", text: ""), "en")
    }

    func test_normalized_usesFallbackThenEnglishDefault() {
        XCTAssertEqual(TranscriptLanguage.normalized(reported: nil, fallback: "zh", text: ""), "zh")
        XCTAssertEqual(TranscriptLanguage.normalized(reported: nil, fallback: nil, text: ""), "en")
    }
}
