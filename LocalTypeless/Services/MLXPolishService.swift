import Foundation

enum MLXPolishError: LocalizedError {
    case modelNotReady
    case emptyInput
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return String(localized: "Polish model is not loaded")
        case .emptyInput:
            return String(localized: "Empty transcript")
        case .generationFailed(let message):
            return String(localized: "Polish generation failed: \(message)")
        }
    }
}

// @unchecked Sendable: stored fields are `let` and the manager is an actor.
final class MLXPolishService: PolishService, @unchecked Sendable {

    private let manager: any PolishModelManaging

    init(manager: any PolishModelManaging) {
        self.manager = manager
    }

    func polish(_ transcript: Transcript, prompt: String) async throws -> String {
        let raw = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw MLXPolishError.emptyInput }

        try await manager.ensureReady(.polishQwen25_3bInstruct4bit)

        let effectivePrompt = prompt.isEmpty
            ? DefaultPrompts.polish(for: transcript.language)
            : prompt

        do {
            let result = try await manager.generate(system: effectivePrompt, user: raw)
            return result.isEmpty ? raw : result
        } catch {
            throw MLXPolishError.generationFailed(error.localizedDescription)
        }
    }
}
