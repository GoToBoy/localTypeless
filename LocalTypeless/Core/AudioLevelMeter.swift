import Foundation
import Accelerate

/// Thread-safe snapshot of the current audio capture's loudness, used to
/// drive the on-screen recording HUD.
///
/// The `Recorder` tap runs on Core Audio's IO thread and calls `record(samples:)`
/// many times per second. The SwiftUI HUD runs on the main thread and reads
/// `smoothedLevel` / `history(count:)` on every frame tick. Cross-thread
/// access is protected by a single `NSLock` — no actor isolation here because
/// the writer is Core Audio (not Swift concurrency).
final class AudioLevelMeter: @unchecked Sendable {

    private let lock = NSLock()
    /// Attack-biased exponential moving average of instantaneous RMS, in [0, 1].
    /// Tracks loud onsets quickly and decays slowly so bars don't snap to
    /// zero between syllables.
    private var _smoothed: Float = 0
    private var _startedAt: Date?
    /// Ring buffer of recent smoothed levels. Snapshots of this drive the
    /// bar heights in the HUD — index 0 = oldest visible frame.
    private var _history: [Float]
    private var _historyHead: Int = 0

    init(historySize: Int = 64) {
        precondition(historySize > 0)
        _history = Array(repeating: 0, count: historySize)
    }

    // MARK: - Writer (audio thread)

    /// Feed one converted audio chunk from the Recorder tap.
    /// Computes RMS via Accelerate, applies a generous gain (speech RMS is
    /// small — typically 0.02–0.2 for normal talking), and updates the
    /// smoothed level + history.
    func record(samples: [Float]) {
        guard !samples.isEmpty else { return }
        var rms: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            vDSP_rmsqv(ptr.baseAddress!, 1, &rms, vDSP_Length(samples.count))
        }
        // Gain of 8 maps typical speech into a pleasant visual range. Clip
        // at 1 so peaks don't push the UI off the top of the pill.
        let gained = min(1.0, max(0.0, rms * 8))
        lock.lock(); defer { lock.unlock() }
        // Asymmetric smoothing: jump fast on loud onsets, fall slowly so
        // bars don't pump back to baseline between words.
        let alpha: Float = gained > _smoothed ? 0.5 : 0.12
        _smoothed += alpha * (gained - _smoothed)
        _history[_historyHead] = _smoothed
        _historyHead = (_historyHead &+ 1) % _history.count
    }

    // MARK: - Session lifecycle

    /// Begin a new capture: reset history to zero and stamp `startedAt` so
    /// the elapsed-time view has something to count from.
    func beginSession() {
        lock.lock(); defer { lock.unlock() }
        _startedAt = Date()
        _smoothed = 0
        for i in 0..<_history.count { _history[i] = 0 }
        _historyHead = 0
    }

    func endSession() {
        lock.lock(); defer { lock.unlock() }
        _startedAt = nil
    }

    // MARK: - Reader (main thread)

    var startedAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return _startedAt
    }

    var smoothedLevel: Float {
        lock.lock(); defer { lock.unlock() }
        return _smoothed
    }

    /// Returns the `count` most-recent smoothed levels, oldest → newest.
    /// Shorter than history capacity is padded with zeros on the left.
    func history(count: Int) -> [Float] {
        precondition(count > 0)
        lock.lock(); defer { lock.unlock() }
        let cap = _history.count
        let n = Swift.min(count, cap)
        var out = [Float](repeating: 0, count: count)
        // Copy oldest-to-newest from the ring, starting at (head - n).
        for i in 0..<n {
            let idx = ((_historyHead - n + i) % cap + cap) % cap
            out[count - n + i] = _history[idx]
        }
        return out
    }
}
