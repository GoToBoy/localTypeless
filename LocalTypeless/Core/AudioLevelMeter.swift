import Accelerate
import Foundation

/// Thread-safe snapshot of the current audio capture's loudness, used to
/// drive the on-screen recording HUD.
final class AudioLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private let silenceThreshold: Float
    private let activeHoldFrames: Int
    private let minimumSpeechFrames: Int
    private var smoothed: Float = 0
    private var _startedAt: Date?
    private var levels: [Float]
    private var head = 0
    private var voiceHoldRemaining = 0
    private var speechFrameCount = 0
    private var maxRMS: Float = 0

    init(
        historySize: Int = 64,
        silenceThreshold: Float = 0.006,
        activeHoldFrames: Int = 3,
        minimumSpeechFrames: Int = 3
    ) {
        precondition(historySize > 0)
        precondition(silenceThreshold >= 0)
        precondition(activeHoldFrames >= 0)
        precondition(minimumSpeechFrames > 0)
        self.silenceThreshold = silenceThreshold
        self.activeHoldFrames = activeHoldFrames
        self.minimumSpeechFrames = minimumSpeechFrames
        levels = Array(repeating: 0, count: historySize)
    }

    func beginSession() {
        lock.lock()
        defer { lock.unlock() }
        _startedAt = Date()
        smoothed = 0
        levels = Array(repeating: 0, count: levels.count)
        head = 0
        voiceHoldRemaining = 0
        speechFrameCount = 0
        maxRMS = 0
    }

    func endSession() {
        lock.lock()
        defer { lock.unlock() }
        _startedAt = nil
    }

    func record(samples: [Float]) {
        guard !samples.isEmpty else { return }

        var rms: Float = 0
        samples.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            vDSP_rmsqv(baseAddress, 1, &rms, vDSP_Length(samples.count))
        }

        let isVoiceFrame = rms >= silenceThreshold
        let gatedLevel = isVoiceFrame ? min(1, max(0, (rms - silenceThreshold) * 11)) : 0
        lock.lock()
        defer { lock.unlock() }

        maxRMS = max(maxRMS, rms)
        if isVoiceFrame {
            voiceHoldRemaining = activeHoldFrames
            speechFrameCount += 1
        } else if voiceHoldRemaining > 0 {
            voiceHoldRemaining -= 1
        }

        let target = isVoiceFrame ? gatedLevel : 0
        let alpha: Float = target > smoothed ? 0.5 : 0.36
        smoothed += alpha * (target - smoothed)
        if !isVoiceFrame, voiceHoldRemaining == 0, smoothed < 0.02 {
            smoothed = 0
        }
        levels[head] = smoothed
        head = (head + 1) % levels.count
    }

    var startedAt: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _startedAt
    }

    var smoothedLevel: Float {
        lock.lock()
        defer { lock.unlock() }
        return smoothed
    }

    var isVoiceActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return voiceHoldRemaining > 0
    }

    var hasMeaningfulSpeech: Bool {
        lock.lock()
        defer { lock.unlock() }
        return speechFrameCount >= minimumSpeechFrames
    }

    var peakRMS: Float {
        lock.lock()
        defer { lock.unlock() }
        return maxRMS
    }

    func history(count: Int) -> [Float] {
        precondition(count > 0)
        lock.lock()
        defer { lock.unlock() }

        let cappedCount = Swift.min(count, levels.count)
        var output = Array(repeating: Float(0), count: count)
        for index in 0..<cappedCount {
            let ringIndex = ((head - cappedCount + index) % levels.count + levels.count) % levels.count
            output[count - cappedCount + index] = levels[ringIndex]
        }
        return output
    }
}
