import Foundation

/// Single source of truth for where on-device model weights live.
///
/// We pin downloads under `~/Library/Application Support/local-typeless/models/`
/// so that app rebuilds, updates, or macOS Caches purges don't wipe multi-GB
/// model weights. Both WhisperKit and MLX use swift-transformers' `HubApi`,
/// which lays files out as `<downloadBase>/models/<repo>/<variant>/` — the
/// same `root` URL therefore works for both.
enum ModelStorage {
    static let root: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = base
            .appendingPathComponent("local-typeless", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }()

    /// Moves previously-downloaded weights from their legacy default locations
    /// into `root`, so existing users don't re-download gigabytes after this
    /// change ships. No-op once the destination exists.
    static func migrateLegacyCachesIfNeeded() {
        let fm = FileManager.default

        // WhisperKit default was ~/Documents/huggingface/models/<org>/<repo>/<variant>
        let legacyWhisper = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc",
                                    isDirectory: true)
        let newWhisper = root
            .appendingPathComponent("models/argmaxinc", isDirectory: true)
        migrate(from: legacyWhisper, to: newWhisper, fm: fm)

        // MLX default was ~/Library/Caches/models/<org>/<repo>
        let legacyMLX = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models/mlx-community", isDirectory: true)
        let newMLX = root
            .appendingPathComponent("models/mlx-community", isDirectory: true)
        migrate(from: legacyMLX, to: newMLX, fm: fm)
    }

    private static func migrate(from src: URL, to dst: URL, fm: FileManager) {
        guard fm.fileExists(atPath: src.path),
              !fm.fileExists(atPath: dst.path) else { return }
        try? fm.createDirectory(at: dst.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? fm.moveItem(at: src, to: dst)
    }

    /// Returns `true` when the expected weights for `kind` already exist on
    /// disk under `root`. Used at launch to decide whether to mark a model
    /// `.downloaded` (so the UI doesn't pretend the user needs to download
    /// it again) and to skip straight to load-into-RAM on first hotkey.
    static func isDownloaded(_ kind: ModelKind) -> Bool {
        let fm = FileManager.default
        switch kind {
        case .asrWhisperLargeV3Turbo:
            // WhisperKit unpacks mlmodelc folders under the variant dir.
            let variantDir = root.appendingPathComponent(
                "models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo",
                isDirectory: true
            )
            guard let entries = try? fm.contentsOfDirectory(atPath: variantDir.path)
            else { return false }
            return entries.contains { $0.hasSuffix(".mlmodelc") }
        case .polishQwen25_3bInstruct4bit:
            // MLX Qwen2.5-3B-Instruct-4bit ships a single safetensors blob
            // alongside tokenizer/config JSON. Presence of weights + config
            // is enough to skip re-download.
            let repoDir = root.appendingPathComponent(
                "models/mlx-community/Qwen2.5-3B-Instruct-4bit",
                isDirectory: true
            )
            let weights = repoDir.appendingPathComponent("model.safetensors")
            let config = repoDir.appendingPathComponent("config.json")
            return fm.fileExists(atPath: weights.path)
                && fm.fileExists(atPath: config.path)
        }
    }
}
