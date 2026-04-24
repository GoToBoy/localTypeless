import XCTest
import AVFoundation
@testable import LocalTypeless

@MainActor
final class WhisperKitASRServiceTests: XCTestCase {

    /// Set LOCAL_TYPELESS_SKIP_MODEL_TESTS=1 to skip these (for CI without model cache).
    private var shouldSkip: Bool {
        ProcessInfo.processInfo.environment["LOCAL_TYPELESS_SKIP_MODEL_TESTS"] == "1"
    }

    func test_transcribes_english_fixture() async throws {
        try XCTSkipIf(shouldSkip, "Model tests disabled via env flag")

        let samples = try loadFixture(named: "en_hello")
        let buffer = AudioBuffer(maxSeconds: 60, sampleRate: 16_000)
        buffer.append(samples)

        let store = ModelStatusStore()
        let manager = WhisperKitModelManager(store: store)
        let asr = WhisperKitASRService(manager: manager)

        let transcript = try await asr.transcribe(buffer)
        XCTAssertFalse(transcript.text.isEmpty)
        XCTAssertTrue(transcript.text.lowercased().contains("dictation")
                      || transcript.text.lowercased().contains("test"))
        XCTAssertEqual(transcript.language.prefix(2), "en")
    }

    func test_transcribes_chinese_fixture() async throws {
        try XCTSkipIf(shouldSkip, "Model tests disabled via env flag")

        guard let url = Bundle(for: type(of: self)).url(forResource: "zh_hello",
                                                        withExtension: "wav") else {
            throw XCTSkip("zh_hello.wav fixture not present")
        }
        let samples = try decodeWav(at: url)
        let buffer = AudioBuffer(maxSeconds: 60, sampleRate: 16_000)
        buffer.append(samples)

        let store = ModelStatusStore()
        let manager = WhisperKitModelManager(store: store)
        let asr = WhisperKitASRService(manager: manager)

        let transcript = try await asr.transcribe(buffer)
        XCTAssertFalse(transcript.text.isEmpty)
        XCTAssertEqual(transcript.language.prefix(2), "zh")
    }

    // MARK: - Helpers

    private func loadFixture(named name: String) throws -> [Float] {
        guard let url = Bundle(for: type(of: self)).url(forResource: name,
                                                        withExtension: "wav") else {
            throw XCTSkip("\(name).wav fixture not present")
        }
        return try decodeWav(at: url)
    }

    private func decodeWav(at url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 16_000,
                                   channels: 1,
                                   interleaved: false)!
        let frameCount = AVAudioFrameCount(file.length)
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: frameCount) else {
            return []
        }
        try file.read(into: buf)

        // Convert to 16 kHz mono Float32.
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let outBuf = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: frameCount) else {
            return []
        }
        var error: NSError?
        converter.convert(to: outBuf, error: &error) { _, status in
            status.pointee = .haveData
            return buf
        }
        if let error { throw error }
        let ptr = outBuf.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
    }
}
