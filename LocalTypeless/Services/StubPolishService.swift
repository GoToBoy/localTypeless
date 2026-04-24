import Foundation

/// Phase-1 stub that performs trivial text cleanup without a model.
/// Replaced by an MLX-backed implementation in Phase 3.
final class StubPolishService: PolishService {

    private static let englishFillers: Set<String> = ["um", "uh", "like", "you", "know"]

    func polish(_ transcript: Transcript, prompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: 50_000_000)
        if transcript.language == "en" {
            return polishEnglish(transcript.text)
        } else {
            return transcript.text
        }
    }

    private func polishEnglish(_ raw: String) -> String {
        let words = raw.split(separator: " ").filter { w in
            !Self.englishFillers.contains(w.lowercased())
        }
        guard let first = words.first else { return "" }
        var rebuilt = first.prefix(1).uppercased() + first.dropFirst()
        for w in words.dropFirst() {
            rebuilt += " " + w
        }
        if !rebuilt.hasSuffix(".") && !rebuilt.hasSuffix("?") && !rebuilt.hasSuffix("!") {
            rebuilt += "."
        }
        return rebuilt
    }
}
