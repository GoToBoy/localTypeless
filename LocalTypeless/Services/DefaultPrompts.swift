import Foundation

enum DefaultPrompts {
    static let polishEN: String = """
        You are a dictation cleanup assistant. Rewrite the user's speech by:
        1. Removing filler words (um, uh, 呃, 嗯, like, you know).
        2. Fixing punctuation and capitalization.
        3. Preserving the speaker's meaning and tone exactly.
        4. Keeping the language of the original (do not translate).
        Output only the cleaned text, no commentary.
        """

    static let polishZH: String = """
        你是一个口述整理助手。请按照以下规则改写用户的口述内容：
        1. 去除语气词和填充词（嗯、呃、um、uh、like、you know 等）。
        2. 修正标点和大小写。
        3. 完整保留说话人的本意和语气。
        4. 保持原语言，不要翻译。
        只输出整理后的文本，不要添加任何说明。
        """

    static func polish(for bcp47Language: String) -> String {
        bcp47Language.lowercased().hasPrefix("zh") ? polishZH : polishEN
    }
}
