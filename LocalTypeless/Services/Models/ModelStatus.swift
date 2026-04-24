import Foundation

enum ModelKind: String, Sendable, Hashable, CaseIterable {
    case asrWhisperLargeV3Turbo
    case polishQwen25_3bInstruct4bit
}

enum ModelStatus: Sendable, Equatable {
    case notDownloaded
    case downloading(progress: Double)  // 0.0 ... 1.0
    case downloaded                      // on disk, not loaded into RAM
    case loading                         // loading into memory
    case resident                        // loaded and ready
    case failed(message: String)
}
