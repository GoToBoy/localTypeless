import AVFoundation
import Foundation

/// Saves raw PCM audio to WAV files and prunes files older than a given age.
///
/// Thread-safety: `directory` is immutable after init and `FileManager.default` is
/// documented as thread-safe for the operations used here, so `@unchecked Sendable`
/// is safe. Do NOT mutate `directory` after init.
final class AudioStore: @unchecked Sendable {

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns `~/Library/Application Support/local-typeless/audio/`.
    static func defaultDirectory() throws -> URL {
        let app = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return app.appendingPathComponent("local-typeless/audio", isDirectory: true)
    }

    /// Write `samples` as a mono Float32 WAV file and return its URL.
    @discardableResult
    func save(samples: [Float], sampleRate: Double) throws -> URL {
        let url = directory.appendingPathComponent("\(UUID().uuidString).wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        )!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            let dst = buffer.floatChannelData!.pointee
            dst.update(from: ptr.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
        return url
    }

    /// Remove WAV files whose modification date is older than `days` days ago.
    func pruneOlderThan(days: Int) throws {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(TimeInterval(-days) * 86_400)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for url in urls {
            let mtime = (try? url.resourceValues(
                forKeys: [.contentModificationDateKey])
            )?.contentModificationDate
            if let mtime, mtime < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
