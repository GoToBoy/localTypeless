import Foundation
@preconcurrency import AVFoundation

@MainActor
final class Recorder {

    private let engine = AVAudioEngine()
    private let buffer: AudioBuffer
    private var isRunning = false
    private let targetSampleRate: Double = 16_000

    init(buffer: AudioBuffer) {
        self.buffer = buffer
    }

    func start() throws {
        guard !isRunning else { return }
        buffer.reset()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterCreationFailed
        }

        // AudioBuffer is thread-safe via NSLock; capture it directly to avoid
        // touching any @MainActor-isolated state inside the tap closure.
        let tapBuffer = buffer
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { pcm, _ in
            let outFrameCapacity = AVAudioFrameCount(
                Double(pcm.frameLength) * 16_000 / inputFormat.sampleRate
            )
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrameCapacity) else {
                return
            }
            var err: NSError?
            let status = converter.convert(to: outBuf, error: &err) { _, outStatus in
                outStatus.pointee = .haveData
                return pcm
            }
            if status == .error {
                Log.recorder.error("converter error: \(err?.localizedDescription ?? "unknown", privacy: .public)")
                return
            }
            guard let chan = outBuf.floatChannelData?[0] else { return }
            let count = Int(outBuf.frameLength)
            let samples = Array(UnsafeBufferPointer(start: chan, count: count))
            tapBuffer.append(samples)
        }

        try engine.start()
        isRunning = true
        Log.recorder.info("recording started")
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        Log.recorder.info("recording stopped: \(self.buffer.durationSeconds, privacy: .public) s captured")
    }

    enum RecorderError: Error {
        case formatCreationFailed
        case converterCreationFailed
    }
}
