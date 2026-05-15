#if !APPLE_SILICON_ENGINE
import Foundation
@preconcurrency import SwiftWhisper

/// Manages the lifecycle of a single GGML whisper.cpp model: downloads it from
/// the Hugging Face mirror on first use, loads it into a `Whisper` instance,
/// and unloads on request.
///
/// Storage: `~/Library/Application Support/local-typeless/models/ggml-small.bin`
///
/// Download streams progress through `URLSessionDownloadDelegate` so the UI
/// can show a real percentage — ~470 MB takes long enough that an opaque spinner
/// would feel hung.
actor WhisperCppModelManager: ModelLifecycle {

    private let store: ModelStatusStore
    private var whisper: Whisper?
    private var inFlight: Task<Void, Error>?

    /// The only kind this manager handles. Bigger / smaller GGML variants
    /// would each get their own `ModelKind` case and either a separate
    /// manager or a switch over `kind` here.
    private let modelKind: ModelKind = .asrWhisperCppSmall

    /// Public mirror of GGML models maintained by the whisper.cpp project.
    /// `ggml-small.bin` is ~465 MiB (487,601,967 bytes) and the smallest
    /// variant with usable Chinese accuracy.
    ///
    /// Pinned to a specific HuggingFace commit so that an upstream rev — or,
    /// in the worst case, repo tampering — can't silently swap the bytes
    /// under us. To bump: replace the SHA with the new tree commit's hash.
    /// SHA-256 of the pinned content: `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b`
    private let modelURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.bin"
    )!

    init(store: ModelStatusStore) {
        self.store = store
    }

    var whisperInstance: Whisper? { whisper }

    func ensureDownloaded(_ kind: ModelKind) async throws {
        guard kind == modelKind else { throw ModelManagerError.unsupportedKind(kind) }
        let modelFile = try Self.modelFileURL()
        if FileManager.default.fileExists(atPath: modelFile.path) {
            // Already on disk. If we haven't loaded yet, reflect that as
            // .downloaded; if we're already resident, leave the status alone.
            if whisper == nil {
                await MainActor.run { store.set(.downloaded, for: kind) }
            }
            return
        }
        try await downloadFile(to: modelFile, kind: kind)
        await MainActor.run { store.set(.downloaded, for: kind) }
    }

    func ensureReady(_ kind: ModelKind) async throws {
        guard kind == modelKind else { throw ModelManagerError.unsupportedKind(kind) }
        if whisper != nil {
            await MainActor.run { store.set(.resident, for: kind) }
            return
        }
        if let existing = inFlight {
            try await existing.value
            return
        }

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.load(kind: kind)
        }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    private func downloadFile(to modelFile: URL, kind: ModelKind) async throws {
        await MainActor.run { store.set(.downloading(progress: 0.0), for: kind) }
        do {
            let storeRef = store
            let downloader = GGMLDownloader { progress in
                Task { @MainActor in
                    storeRef.set(.downloading(progress: progress), for: kind)
                }
            }
            let tempURL = try await downloader.download(from: modelURL)
            try? FileManager.default.removeItem(at: modelFile)
            try FileManager.default.moveItem(at: tempURL, to: modelFile)
        } catch {
            await MainActor.run {
                store.set(.failed(message: error.localizedDescription), for: kind)
            }
            throw ModelManagerError.initializationFailed(error.localizedDescription)
        }
    }

    private func load(kind: ModelKind) async throws {
        let modelFile = try Self.modelFileURL()

        if !FileManager.default.fileExists(atPath: modelFile.path) {
            try await downloadFile(to: modelFile, kind: kind)
        }

        // Sanity check before handing the file to SwiftWhisper's `Whisper`
        // init — that init takes a non-optional OpaquePointer and crashes on
        // first transcribe if `whisper_init_from_file` returned NULL (e.g.
        // a truncated download). ggml-small.bin is ~466 MiB; anything well
        // under 100 MB is certainly broken.
        let attrs = try FileManager.default.attributesOfItem(atPath: modelFile.path)
        let size = (attrs[.size] as? Int64) ?? 0
        guard size > 100 * 1024 * 1024 else {
            try? FileManager.default.removeItem(at: modelFile)
            await MainActor.run {
                store.set(.failed(message: String(localized: "Downloaded model file is too small — try again")), for: kind)
            }
            throw ModelManagerError.initializationFailed(
                "GGML file size \(size) bytes is below the 100 MB sanity threshold"
            )
        }

        await MainActor.run { store.set(.loading, for: kind) }
        let w = Whisper(fromFileURL: modelFile)
        self.whisper = w
        await MainActor.run { store.set(.resident, for: kind) }
    }

    func unload(_ kind: ModelKind) async {
        guard kind == modelKind else { return }
        whisper = nil
        await MainActor.run { store.set(.downloaded, for: kind) }
    }

    static func modelFileURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("local-typeless/models", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ggml-small.bin")
    }
}

/// Bridges `URLSessionDownloadDelegate`'s per-chunk callback into async/await
/// land. `URLSession.shared.download(from:)` only resolves at completion, so
/// it can't drive the `.downloading(progress:)` UI state during a 470 MB pull.
///
/// One-shot: a single `download(from:)` call constructs a private session,
/// resumes its task, resumes the continuation on completion, and tears the
/// session down. Reuse for a second download requires a new instance.
private final class GGMLDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private let lock = NSLock()

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
        super.init()
    }

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            lock.lock()
            continuation = cont
            lock.unlock()

            let config = URLSessionConfiguration.default
            let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            session = s
            s.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        let s = session
        session = nil
        lock.unlock()
        cont?.resume(with: result)
        s?.finishTasksAndInvalidate()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The framework deletes `location` after this callback returns, so
        // copy it somewhere stable that the caller can later move into place.
        do {
            let stable = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".ggml")
            try? FileManager.default.removeItem(at: stable)
            try FileManager.default.moveItem(at: location, to: stable)

            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                try? FileManager.default.removeItem(at: stable)
                finish(.failure(ModelManagerError.initializationFailed(
                    "GGML download failed: HTTP \(http.statusCode)"
                )))
                return
            }

            finish(.success(stable))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
#endif
