import Foundation

struct Transcript: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        let text: String
        let startSeconds: Double
        let endSeconds: Double
    }

    let text: String
    let language: String
    let segments: [Segment]
}

protocol ASRService: AnyObject, Sendable {
    func transcribe(_ audio: AudioBuffer) async throws -> Transcript
}

/// Language mode the user can force on ASR. `nil` means auto-detect.
/// Lives with the protocol (rather than the WhisperKit implementation) so
/// `DictationEngine.setASROptions(_:)` is available on every build.
struct ASROptions: Sendable {
    var forcedLanguage: String?  // BCP-47 ("en", "zh") — nil = auto
    static let auto = ASROptions(forcedLanguage: nil)
}

enum TranscriptLanguage {
    static func normalized(reported: String?, fallback: String? = nil, text: String) -> String {
        if containsHanText(text) {
            return "zh"
        }

        if let reported = canonicalCode(reported) {
            return reported
        }
        if let fallback = canonicalCode(fallback) {
            return fallback
        }
        return "en"
    }

    private static func canonicalCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let lowered = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        guard !lowered.isEmpty else { return nil }

        if lowered.hasPrefix("zh") || lowered == "chinese" || lowered == "mandarin" {
            return "zh"
        }
        if lowered.hasPrefix("en") || lowered == "english" {
            return "en"
        }
        return lowered
    }

    private static func containsHanText(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,   // CJK Unified Ideographs Extension A
                 0x4E00...0x9FFF,   // CJK Unified Ideographs
                 0xF900...0xFAFF,   // CJK Compatibility Ideographs
                 0x20000...0x2A6DF, // CJK Unified Ideographs Extension B
                 0x2A700...0x2B73F, // Extension C
                 0x2B740...0x2B81F, // Extension D
                 0x2B820...0x2CEAF, // Extension E/F
                 0x30000...0x3134F: // Extension G/H
                return true
            default:
                return false
            }
        }
    }
}
