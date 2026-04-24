import Foundation

enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case polishing
    case injecting
    case error(String)
}
