import Foundation

enum TranscriptTextNormalizer {
    static func unpolishedOutput(for transcript: Transcript) -> String {
        finalOutput(transcript.text, transcript: transcript)
    }

    static func finalOutput(_ candidate: String, transcript: Transcript) -> String {
        let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = TranscriptLanguage.normalized(
            reported: transcript.language,
            text: text
        )
        guard language == "zh" else {
            return collapseWhitespace(in: text)
        }
        return normalizeCJKSpacing(in: text)
    }

    private static func normalizeCJKSpacing(in text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = scalars.startIndex
        var emittedSpace = false

        while index < scalars.endIndex {
            let scalar = scalars[index]
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                let previous = previousNonWhitespace(before: index, in: scalars)
                let next = nextNonWhitespace(after: index, in: scalars)
                if shouldDropSpace(previous: previous, next: next) {
                    emittedSpace = false
                } else if !emittedSpace {
                    output.append(" ")
                    emittedSpace = true
                }
            } else {
                output.append(scalar)
                emittedSpace = false
            }
            index = scalars.index(after: index)
        }

        return String(output).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseWhitespace(in text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func previousNonWhitespace(
        before index: [UnicodeScalar].Index,
        in scalars: [UnicodeScalar]
    ) -> UnicodeScalar? {
        var cursor = index
        while cursor > scalars.startIndex {
            cursor = scalars.index(before: cursor)
            let scalar = scalars[cursor]
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return scalar
            }
        }
        return nil
    }

    private static func nextNonWhitespace(
        after index: [UnicodeScalar].Index,
        in scalars: [UnicodeScalar]
    ) -> UnicodeScalar? {
        var cursor = scalars.index(after: index)
        while cursor < scalars.endIndex {
            let scalar = scalars[cursor]
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return scalar
            }
            cursor = scalars.index(after: cursor)
        }
        return nil
    }

    private static func shouldDropSpace(previous: UnicodeScalar?, next: UnicodeScalar?) -> Bool {
        guard let previous, let next else { return false }
        return isCJKContext(previous) || isCJKContext(next)
    }

    private static func isCJKContext(_ scalar: UnicodeScalar) -> Bool {
        isHan(scalar) || isCJKPunctuation(scalar)
    }

    private static func isHan(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF,
             0x30000...0x3134F:
            return true
        default:
            return false
        }
    }

    private static func isCJKPunctuation(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F, 0xFF00...0xFFEF:
            return true
        default:
            return "，。！？；：、,.!?;:)]}）】》".unicodeScalars.contains(scalar)
        }
    }
}
