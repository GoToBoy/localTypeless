import XCTest
@testable import LocalTypeless

final class TranscriptTextNormalizerTests: XCTestCase {
    func test_removes_spaces_between_chinese_characters() {
        let transcript = Transcript(
            text: "我 们 明 天 发布 一 下。",
            language: "zh",
            segments: []
        )

        XCTAssertEqual(
            TranscriptTextNormalizer.unpolishedOutput(for: transcript),
            "我们明天发布一下。"
        )
    }

    func test_keeps_spaces_between_latin_words_in_mixed_chinese() {
        let transcript = Transcript(
            text: "Mac mini 很 好, OpenAI 今天 发布",
            language: "zh",
            segments: []
        )

        XCTAssertEqual(
            TranscriptTextNormalizer.unpolishedOutput(for: transcript),
            "Mac mini很好,OpenAI今天发布"
        )
    }

    func test_english_collapses_extra_whitespace() {
        let transcript = Transcript(
            text: "hello   world\nagain",
            language: "en",
            segments: []
        )

        XCTAssertEqual(
            TranscriptTextNormalizer.unpolishedOutput(for: transcript),
            "hello world again"
        )
    }

    func test_finalOutput_normalizesPolishedChineseText() {
        let transcript = Transcript(
            text: "我来测试一下",
            language: "zh",
            segments: []
        )

        XCTAssertEqual(
            TranscriptTextNormalizer.finalOutput("我 来 测试 一下 当前 的 一个 实际 状态", transcript: transcript),
            "我来测试一下当前的一个实际状态"
        )
    }
}
