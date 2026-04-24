import Foundation
@preconcurrency import AVFoundation
import CoreAudio

@MainActor
final class Recorder {

    private let engine = AVAudioEngine()
    private let buffer: AudioBuffer
    private let meter: AudioLevelMeter
    private var isRunning = false
    private let targetSampleRate: Double = 16_000

    init(buffer: AudioBuffer, meter: AudioLevelMeter) {
        self.buffer = buffer
        self.meter = meter
        // Eagerly resolve the default input device so the HAL isn't racing
        // us on the user's first hotkey press. Without this warm-up the
        // first `engine.start()` can fire while
        //   HALDefaultDevice.cpp: Could not find default device
        // is still in flight, which yields a `0ch/0Hz` input format and
        // the `-10868 / nullptr == Tap()` crash chain we fixed above.
        //
        // Touching `inputNode` triggers lazy graph construction and
        // `prepare()` pre-allocates the audio unit render resources.
        _ = engine.inputNode
        engine.prepare()
    }

    func start() throws {
        guard !isRunning else { return }
        buffer.reset()
        meter.beginSession()

        let input = engine.inputNode

        // Defensive cleanup. If a prior `start()` failed mid-way (e.g.
        // `engine.start()` threw after we installed the tap, or the HAL
        // races on default-input resolution at launch), AVAudioEngine
        // keeps the tap object attached to the node even though our
        // `stop()` never ran (it's guarded by `isRunning`). The next
        // `installTap(onBus: 0, …)` would then hit the ObjC assertion
        //   `required condition is false: nullptr == Tap()`
        // and terminate the process with an uncaught NSException (Swift
        // can't catch those). Tearing the bus down here first is a no-op
        // in the clean case and the safety net in the retry case.
        input.removeTap(onBus: 0)

        // Diagnostic-only Core Audio probe. We do NOT gate `start()` on
        // this any more — on real machines the property read can return 0
        // streams for perfectly healthy microphones (virtual audio devices,
        // some BT codecs, certain TCC-sandbox interactions), and failing
        // closed on a working mic is worse UX than trusting the format
        // pre-flight + SafeAudioTap shim below. The probe is still useful
        // as a log hint when we later triage why installTap fell over.
        if !Self.defaultInputDeviceHasInputStreams() {
            Log.recorder.info(
                "core-audio probe reports no input streams — continuing with live-format check"
            )
        }

        // Pre-flight: bail early if the input node has no live format.
        //
        // On macOS the default input device can momentarily report
        // `0 ch, 0 Hz` — e.g. when HALDefaultDevice hasn't resolved the
        // default input yet right at launch, or when another process just
        // released exclusive access. Passing that through to installTap
        // produces AVFAudio's "-10868 format not supported" error, and
        // AVAudioEngine then keeps a half-configured tap on the node
        // (bug #1 above). Skipping installTap entirely means the user can
        // just retry the hotkey once the device is ready.
        let liveInputFormat = input.outputFormat(forBus: 0)
        guard liveInputFormat.channelCount > 0, liveInputFormat.sampleRate > 0 else {
            meter.endSession()
            Log.recorder.error(
                "input device not ready: \(String(describing: liveInputFormat), privacy: .public)"
            )
            throw RecorderError.inputDeviceNotReady
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            meter.endSession()
            throw RecorderError.formatCreationFailed
        }

        // Pass `format: nil` so the tap adopts the input node's *live* format.
        //
        // Passing `input.outputFormat(forBus: 0)` seems like it should work —
        // and often does on iOS — but on macOS that API can return a format
        // that doesn't byte-for-byte match what AVAudioEngine actually uses
        // once the engine starts (e.g. channel-layout tag differences against
        // a 2ch 44.1kHz Float32 deinterleaved built-in input). installTap
        // then aborts the process with `Failed to create tap due to format
        // mismatch`. Deferring to nil sidesteps the comparison entirely.
        //
        // The downside is we no longer know the concrete input format until
        // the first buffer arrives — so the AVAudioConverter is built
        // lazily inside the tap, keyed off `pcm.format`. The tap block is
        // invoked serially from Core Audio's IO thread, so holding that
        // state in a reference-typed helper is safe without locking.
        let tapBuffer = buffer
        let tapMeter = meter
        let state = TapConverterState(
            targetFormat: targetFormat,
            targetSampleRate: targetSampleRate
        )

        // Route through the ObjC shim so an NSException raised inside
        // -installTapOnBus:… (which Swift's `try` can't catch) comes back
        // as an NSError instead of SIGABRT'ing the process. See
        // SafeAudioTap.h for the rationale.
        //
        // Swift bridges `BOOL + NSError**` ObjC methods as `throws`, so the
        // selector `+installTapOn:bus:bufferSize:format:block:error:`
        // imports as `installTap(on:bus:bufferSize:format:block:) throws`.
        do {
            try SafeAudioTap.installTap(
                on: input,
                bus: 0,
                bufferSize: 4096,
                format: nil,
                block: { pcm, _ in
                    state.process(pcm: pcm, into: tapBuffer, meter: tapMeter)
                }
            )
        } catch {
            meter.endSession()
            Log.recorder.error(
                "installTap failed: \(error.localizedDescription, privacy: .public)"
            )
            throw RecorderError.installTapFailed
        }

        // If `engine.start()` throws, undo the tap so the retry path can
        // reinstall cleanly. Without this, the dangling tap would reproduce
        // the `nullptr == Tap()` crash from the next hotkey press.
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            meter.endSession()
            throw error
        }
        isRunning = true
        Log.recorder.info("recording started")
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        meter.endSession()
        isRunning = false
        Log.recorder.info("recording stopped: \(self.buffer.durationSeconds, privacy: .public) s captured")
    }

    enum RecorderError: LocalizedError {
        case formatCreationFailed
        case converterCreationFailed
        case inputDeviceNotReady
        case installTapFailed

        var errorDescription: String? {
            switch self {
            case .formatCreationFailed:    return "Could not create audio format."
            case .converterCreationFailed: return "Could not create audio converter."
            case .inputDeviceNotReady:
                return "Microphone not ready yet. Try the hotkey again in a moment."
            case .installTapFailed:
                return "Audio engine refused to start. Check your microphone settings and try again."
            }
        }
    }

    // MARK: - Core Audio pre-flight

    /// Returns `true` when the current default input device is present *and*
    /// has at least one input stream. Returns `false` when macOS has no
    /// default input at all, or when the default input is an output-only
    /// device (the AirPods case — HAL happily reports them as "default
    /// input" even though they can't actually capture). We use this to
    /// short-circuit before AVAudioEngine's installTap, whose failure mode
    /// on that input is an uncatchable NSException.
    ///
    /// All I/O is synchronous Core Audio property reads — no allocations,
    /// no thread hops — so it's cheap to call on every hotkey press.
    static func defaultInputDeviceHasInputStreams() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let sysObj = AudioObjectID(kAudioObjectSystemObject)
        let status = AudioObjectGetPropertyData(sysObj, &addr, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return false }

        var streamsAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize = UInt32(0)
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &streamsAddr, 0, nil, &streamsSize)
        guard sizeStatus == noErr else { return false }
        return streamsSize >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    /// Returns `true` when the Mac appears to have at least one usable audio
    /// capture path. We prefer the current default input device, but fall back
    /// to AVFoundation's device enumeration so machines without a configured
    /// default input can still avoid a false "no hardware" warning when a mic
    /// is physically present.
    static func hasUsableRecordingHardware() -> Bool {
        if defaultInputDeviceHasInputStreams() {
            return true
        }
        return !AVCaptureDevice.devices(for: .audio).isEmpty
    }
}

/// Holds the converter and the last-seen input format across tap callbacks.
///
/// Core Audio invokes the tap block serially on its IO thread, so plain
/// mutable properties are safe here without a lock. `@unchecked Sendable`
/// lets the Sendable tap closure capture this without a warning — we're
/// asserting the single-writer invariant that AVAudioEngine gives us.
private final class TapConverterState: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private let targetSampleRate: Double
    private var converter: AVAudioConverter?
    private var lastInputFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat, targetSampleRate: Double) {
        self.targetFormat = targetFormat
        self.targetSampleRate = targetSampleRate
    }

    func process(pcm: AVAudioPCMBuffer, into buffer: AudioBuffer, meter: AudioLevelMeter) {
        let inputFormat = pcm.format
        // Rebuild the converter if the input format drifts (e.g. the user
        // changes input device mid-recording). In the steady state this
        // branch only fires once, on the first buffer.
        if lastInputFormat != inputFormat {
            lastInputFormat = inputFormat
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            if converter == nil {
                Log.recorder.error(
                    "failed to build converter from \(String(describing: inputFormat), privacy: .public)"
                )
            }
        }
        guard let conv = converter else { return }

        let outFrameCapacity = AVAudioFrameCount(
            Double(pcm.frameLength) * targetSampleRate / inputFormat.sampleRate
        )
        guard outFrameCapacity > 0,
              let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrameCapacity)
        else {
            return
        }
        var err: NSError?
        let status = conv.convert(to: outBuf, error: &err) { _, outStatus in
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
        buffer.append(samples)
        meter.record(samples: samples)
    }
}
