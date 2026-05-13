import XCTest
@testable import LocalTypeless

@MainActor
final class DictationPipelineTests: XCTestCase {

    private func makeBuffer() -> AudioBuffer {
        let buf = AudioBuffer(maxSeconds: 2, sampleRate: 16_000)
        buf.append(Array(repeating: 0.0, count: 16_000))
        return buf
    }

    private func makeInput(buffer: AudioBuffer) -> DictationPipeline.Input {
        DictationPipeline.Input(
            audioBuffer: buffer,
            startedAt: Date(),
            targetAppProcessIdentifier: nil,
            targetAppBundleId: "com.example.App",
            targetAppName: "Example",
            polishEnabled: true,
            polishPrompt: "",
            transcribeTimeout: 2,
            polishTimeout: 2,
            saveAudio: false,
            audioRetentionDays: 7
        )
    }

    func test_happyPath_emitsStagesAndPersistsEntry() async throws {
        let history = InMemoryHistoryStore()
        let pipeline = DictationPipeline(.init(
            asr: StubASRService(fixedText: "hello world", language: "en"),
            polish: StubPolishService(),
            injector: NoopTextInjector(),
            historyStore: history,
            audioStore: nil
        ))

        var events: [String] = []
        await pipeline.run(makeInput(buffer: makeBuffer())) { event in
            switch event {
            case .transcribing: events.append("transcribing")
            case .polishing:    events.append("polishing")
            case .injecting:    events.append("injecting")
            case .copyFallback: events.append("copyFallback")
            case .done:         events.append("done")
            case .failed(let m): events.append("failed:\(m)")
            }
        }

        XCTAssertEqual(events, ["transcribing", "polishing", "injecting", "done"])
        let stored = try history.all()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.rawTranscript, "hello world")
        XCTAssertEqual(stored.first?.targetAppBundleId, "com.example.App")
    }

    func test_asrTimeout_emitsFailedAndDoesNotPersist() async throws {
        let history = InMemoryHistoryStore()
        let pipeline = DictationPipeline(.init(
            asr: SlowASRService(delaySeconds: 2),
            polish: StubPolishService(),
            injector: NoopTextInjector(),
            historyStore: history,
            audioStore: nil
        ))

        var input = makeInput(buffer: makeBuffer())
        input = DictationPipeline.Input(
            audioBuffer: input.audioBuffer,
            startedAt: input.startedAt,
            targetAppProcessIdentifier: nil,
            targetAppBundleId: nil,
            targetAppName: nil,
            polishEnabled: true,
            polishPrompt: "",
            transcribeTimeout: 0.1,
            polishTimeout: 1,
            saveAudio: false,
            audioRetentionDays: 7
        )

        var terminal: DictationPipeline.Event?
        await pipeline.run(input) { event in terminal = event }

        if case .failed(let msg) = terminal {
            XCTAssertEqual(msg, "Transcription timed out")
        } else {
            XCTFail("expected .failed, got \(String(describing: terminal))")
        }
        XCTAssertEqual(try history.all().count, 0)
    }

    func test_polishFailure_fallsBackToRawTranscript() async throws {
        let history = InMemoryHistoryStore()
        let injector = RecordingTextInjector()
        let pipeline = DictationPipeline(.init(
            asr: StubASRService(fixedText: "raw transcript", language: "en"),
            polish: ThrowingPolishService(),
            injector: injector,
            historyStore: history,
            audioStore: nil
        ))

        await pipeline.run(makeInput(buffer: makeBuffer())) { _ in }

        XCTAssertEqual(injector.injected, "raw transcript")
        let stored = try history.all()
        XCTAssertEqual(stored.first?.polishedText, "raw transcript")
    }

    func test_polishDisabled_skipsPolishAndUsesRawTranscript() async throws {
        let history = InMemoryHistoryStore()
        let injector = RecordingTextInjector()
        let pipeline = DictationPipeline(.init(
            asr: StubASRService(fixedText: "raw transcript", language: "en"),
            polish: ThrowingPolishService(),
            injector: injector,
            historyStore: history,
            audioStore: nil
        ))

        let base = makeInput(buffer: makeBuffer())
        let input = DictationPipeline.Input(
            audioBuffer: base.audioBuffer,
            startedAt: base.startedAt,
            targetAppProcessIdentifier: nil,
            targetAppBundleId: base.targetAppBundleId,
            targetAppName: base.targetAppName,
            polishEnabled: false,
            polishPrompt: "",
            transcribeTimeout: base.transcribeTimeout,
            polishTimeout: base.polishTimeout,
            saveAudio: base.saveAudio,
            audioRetentionDays: base.audioRetentionDays
        )

        var events: [String] = []
        await pipeline.run(input) { event in
            switch event {
            case .transcribing: events.append("transcribing")
            case .polishing: events.append("polishing")
            case .injecting: events.append("injecting")
            case .done: events.append("done")
            case .copyFallback, .failed: break
            }
        }

        XCTAssertEqual(events, ["transcribing", "injecting", "done"])
        XCTAssertEqual(injector.injected, "raw transcript")
        XCTAssertEqual(try history.all().first?.polishedText, "raw transcript")
    }

    func test_polishDisabled_normalizesChineseSpacing() async throws {
        let history = InMemoryHistoryStore()
        let injector = RecordingTextInjector()
        let pipeline = DictationPipeline(.init(
            asr: StubASRService(fixedText: "我 们 明 天 发布", language: "zh"),
            polish: ThrowingPolishService(),
            injector: injector,
            historyStore: history,
            audioStore: nil
        ))

        let base = makeInput(buffer: makeBuffer())
        let input = DictationPipeline.Input(
            audioBuffer: base.audioBuffer,
            startedAt: base.startedAt,
            targetAppProcessIdentifier: nil,
            targetAppBundleId: base.targetAppBundleId,
            targetAppName: base.targetAppName,
            polishEnabled: false,
            polishPrompt: "",
            transcribeTimeout: base.transcribeTimeout,
            polishTimeout: base.polishTimeout,
            saveAudio: base.saveAudio,
            audioRetentionDays: base.audioRetentionDays
        )

        await pipeline.run(input) { _ in }

        XCTAssertEqual(injector.injected, "我们明天发布")
        XCTAssertEqual(try history.all().first?.rawTranscript, "我 们 明 天 发布")
        XCTAssertEqual(try history.all().first?.polishedText, "我们明天发布")
    }

    func test_polishSuccess_normalizesChineseSpacingBeforeInjection() async throws {
        let history = InMemoryHistoryStore()
        let injector = RecordingTextInjector()
        let pipeline = DictationPipeline(.init(
            asr: StubASRService(fixedText: "我 来 测试 一下 当前 的 一个 实际 状态", language: "zh"),
            polish: StubPolishService(),
            injector: injector,
            historyStore: history,
            audioStore: nil
        ))

        await pipeline.run(makeInput(buffer: makeBuffer())) { _ in }

        XCTAssertEqual(injector.injected, "我来测试一下当前的一个实际状态")
        XCTAssertEqual(try history.all().first?.polishedText, "我来测试一下当前的一个实际状态")
    }

    func test_injectionFallback_emitsCopyFallbackAndStillPersists() async throws {
        let history = InMemoryHistoryStore()
        let pipeline = DictationPipeline(.init(
            asr: StubASRService(fixedText: "hello", language: "en"),
            polish: StubPolishService(),
            injector: NoFocusedWindowTextInjector(),
            historyStore: history,
            audioStore: nil
        ))

        var sawFallback = false
        await pipeline.run(makeInput(buffer: makeBuffer())) { event in
            if case .copyFallback(let text, let reason) = event {
                sawFallback = true
                XCTAssertEqual(text, "Hello.")
                XCTAssertEqual(reason, .noFocusedWindow)
            }
        }

        XCTAssertTrue(sawFallback)
        let stored = try history.all()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.polishedText, "Hello.")
    }
}

// MARK: - Test doubles

private final class InMemoryHistoryStore: HistoryStore {
    private var entries: [DictationEntry] = []
    private var nextId: Int64 = 1

    @discardableResult
    func insert(_ entry: DictationEntry) throws -> Int64 {
        var copy = entry
        copy.id = nextId
        nextId += 1
        entries.append(copy)
        return copy.id!
    }
    func all() throws -> [DictationEntry] { entries }
    func search(query: String) throws -> [DictationEntry] {
        entries.filter { $0.rawTranscript.contains(query) }
    }
    func delete(id: Int64) throws {
        entries.removeAll { $0.id == id }
    }
}

private final class SlowASRService: ASRService {
    let delaySeconds: Double
    init(delaySeconds: Double) { self.delaySeconds = delaySeconds }
    func transcribe(_ audio: AudioBuffer) async throws -> Transcript {
        try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        return Transcript(text: "", language: "en", segments: [])
    }
}

private final class ThrowingPolishService: PolishService {
    struct Boom: Error {}
    func polish(_ transcript: Transcript, prompt: String) async throws -> String {
        throw Boom()
    }
}

/// Subclass of the real injector that skips AX/CGEvent work so tests can run
/// without accessibility permission.
@MainActor
private final class NoopTextInjector: TextInjector {
    override func inject(_ text: String, target: TextInjector.Target?) async throws { /* no-op */ }
}

@MainActor
private final class RecordingTextInjector: TextInjector {
    var injected: String = ""
    override func inject(_ text: String, target: TextInjector.Target?) async throws {
        injected = text
    }
}

@MainActor
private final class NoFocusedWindowTextInjector: TextInjector {
    override func inject(_ text: String, target: TextInjector.Target?) async throws {
        throw TextInjector.InjectionError.noFocusedWindow
    }
}
