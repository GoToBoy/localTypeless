import Foundation

final class StubASRService: ASRService {
    private let fixedText: String
    private let language: String

    init(fixedText: String = "this is a stubbed transcript", language: String = "en") {
        self.fixedText = fixedText
        self.language = language
    }

    func transcribe(_ audio: AudioBuffer) async throws -> Transcript {
        try await Task.sleep(nanoseconds: 100_000_000)
        let seg = Transcript.Segment(
            text: fixedText,
            startSeconds: 0,
            endSeconds: audio.durationSeconds
        )
        return Transcript(text: fixedText, language: language, segments: [seg])
    }
}
