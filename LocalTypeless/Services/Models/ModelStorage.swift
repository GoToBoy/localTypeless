import Foundation

enum ModelStorage {
    static let whisperModelVariant = "openai_whisper-large-v3-v20240930_turbo"
    static let whisperModelRepo = "argmaxinc/whisperkit-coreml"
    static let mlxPolishModelId = "mlx-community/Qwen2.5-3B-Instruct-4bit"

    static func modelsDirectory() throws -> URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask)[0]
            .appendingPathComponent("local-typeless", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir,
                                                withIntermediateDirectories: true)
        return supportDir
    }

    static func isDownloaded(_ kind: ModelKind) -> Bool {
        downloadedModelDirectory(kind) != nil
    }

    static func downloadedModelDirectory(_ kind: ModelKind) -> URL? {
        switch kind {
        case .asrWhisperLargeV3Turbo:
            return whisperModelDirectory()
        case .polishQwen25_3bInstruct4bit:
            return polishModelDirectory()
        }
    }

    private static func whisperModelDirectory() -> URL? {
        guard let base = try? modelsDirectory() else { return nil }
        let repoDir = base
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)

        let exactDir = repoDir.appendingPathComponent(whisperModelVariant, isDirectory: true)
        if hasWhisperModel(in: exactDir) {
            return exactDir
        }

        guard let modelDirs = try? FileManager.default.contentsOfDirectory(
            at: repoDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return nil
        }

        return modelDirs
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first(where: hasWhisperModel(in:))
    }

    private static func polishModelDirectory() -> URL? {
        guard let base = try? modelsDirectory() else { return nil }
        let dir = base
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("mlx-community", isDirectory: true)
            .appendingPathComponent("Qwen2.5-3B-Instruct-4bit", isDirectory: true)

        return hasPolishModel(in: dir) ? dir : nil
    }

    private static func hasWhisperModel(in directory: URL) -> Bool {
        hasDirectory("AudioEncoder.mlmodelc", in: directory)
            && hasDirectory("TextDecoder.mlmodelc", in: directory)
            && hasDirectory("MelSpectrogram.mlmodelc", in: directory)
    }

    private static func hasPolishModel(in dir: URL) -> Bool {
        hasFile("config.json", in: dir)
            && hasFile("tokenizer.json", in: dir)
            && hasFile("model.safetensors", in: dir)
    }

    private static func hasFile(_ name: String, in directory: URL) -> Bool {
        let path = directory.appendingPathComponent(name).path
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private static func hasDirectory(_ name: String, in directory: URL) -> Bool {
        let path = directory.appendingPathComponent(name).path
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
