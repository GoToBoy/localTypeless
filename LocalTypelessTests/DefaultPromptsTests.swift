import XCTest
@testable import LocalTypeless

final class DefaultPromptsTests: XCTestCase {
    func test_en_and_zh_prompts_are_nonempty_and_distinct() {
        let en = DefaultPrompts.polish(for: "en")
        let zh = DefaultPrompts.polish(for: "zh")
        XCTAssertFalse(en.isEmpty)
        XCTAssertFalse(zh.isEmpty)
        XCTAssertNotEqual(en, zh)
    }

    func test_unknown_language_falls_back_to_english() {
        XCTAssertEqual(DefaultPrompts.polish(for: "fr"),
                       DefaultPrompts.polish(for: "en"))
    }

    func test_mentions_filler_words_in_each_language() {
        XCTAssertTrue(DefaultPrompts.polish(for: "en").contains("filler"))
        XCTAssertTrue(DefaultPrompts.polish(for: "zh").contains("语气词")
                      || DefaultPrompts.polish(for: "zh").contains("填充"))
    }
}
