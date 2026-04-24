import Foundation

protocol PolishService: AnyObject, Sendable {
    func polish(_ transcript: Transcript, prompt: String) async throws -> String
}
