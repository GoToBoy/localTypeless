import Foundation

enum ModelKind: String, Sendable, Hashable, CaseIterable {
    // Apple Silicon engine
    case asrWhisperLargeV3Turbo
    case polishQwen25_3bInstruct4bit

    // Portable engine (whisper.cpp GGML files).
    // `small` is the default — ~470 MB on disk, ~600 MB RAM, ~2-3x realtime
    // on Intel CPU, and the practical floor for usable Chinese transcription.
    case asrWhisperCppSmall

    /// Human-readable name for Settings / model-download UI.
    var displayName: String {
        switch self {
        case .asrWhisperLargeV3Turbo:
            return String(localized: "Speech (Whisper Large v3 Turbo)")
        case .polishQwen25_3bInstruct4bit:
            return String(localized: "Polish (Qwen 2.5 3B 4-bit)")
        case .asrWhisperCppSmall:
            return String(localized: "Speech (whisper.cpp small)")
        }
    }
}

enum ModelStatus: Sendable, Equatable {
    case notDownloaded
    case downloading(progress: Double)  // 0.0 ... 1.0
    case downloaded                      // on disk, not loaded into RAM
    case loading                         // loading into memory
    case resident                        // loaded and ready
    case failed(message: String)
}
