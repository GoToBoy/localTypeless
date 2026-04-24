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
