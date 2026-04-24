import Foundation

final class AudioBuffer: @unchecked Sendable {

    let maxSamples: Int
    let sampleRate: Int
    private var samples: [Float] = []
    private let lock = NSLock()

    init(maxSeconds: Int, sampleRate: Int) {
        self.sampleRate = sampleRate
        self.maxSamples = maxSeconds * sampleRate
        self.samples.reserveCapacity(self.maxSamples)
    }

    var sampleCount: Int {
        lock.lock(); defer { lock.unlock() }
        return samples.count
    }

    var durationSeconds: Double {
        Double(sampleCount) / Double(sampleRate)
    }

    func append(_ chunk: [Float]) {
        lock.lock(); defer { lock.unlock() }
        samples.append(contentsOf: chunk)
        if samples.count > maxSamples {
            let overflow = samples.count - maxSamples
            samples.removeFirst(overflow)
        }
    }

    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
    }
}
