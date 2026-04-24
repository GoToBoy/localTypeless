# Phase 2 — WhisperKit ASR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `StubASRService` with a real `WhisperKitASRService` backed by `whisper-large-v3-turbo` CoreML, with first-run model download UI, auto-detection of EN/ZH, and a model-readiness gate on the dictation pipeline.

**Architecture:** Introduce a `ModelManager` facade that owns WhisperKit's lifecycle (download → load → resident → unload). A lightweight `@Observable ModelStatusStore` surfaces state to the UI. `WhisperKitASRService` is a thin adapter from `ASRService.transcribe(_:)` to `WhisperKit.transcribe(audioArray:)`. AppDelegate delegates "can we start now?" to the store, and on first tap shows a SwiftUI download sheet instead of running the pipeline.

**Tech Stack:** WhisperKit (argmaxinc) Swift Package, CoreML, HuggingFace model hub (via WhisperKit's bundled downloader), SwiftUI, existing Phase 1 services.

**Prep:** This plan begins with a Task 0 that cleans up Phase 1 review notes (Sendable conformance, pipeline timeout/cancellation, pasteboard restore delay, error surfacing). Do that first — Phase 2 tasks assume it.

---

## File structure

**Create:**
- `LocalTypeless/Services/Models/ModelStatus.swift` — `enum ModelStatus`, `enum ModelKind`
- `LocalTypeless/Services/Models/ModelStatusStore.swift` — `@Observable` bag holding current status per `ModelKind`
- `LocalTypeless/Services/Models/ModelManager.swift` — protocol + concrete `WhisperKitModelManager`
- `LocalTypeless/Services/WhisperKitASRService.swift` — real ASR service (conforms to `ASRService`)
- `LocalTypeless/UI/ModelDownloadView.swift` — progress sheet
- `LocalTypeless/Support/PipelineTimeout.swift` — `withTimeout(_:_:)` helper
- `LocalTypelessTests/Fixtures/en_hello.wav` — 2–3s English fixture (recorded or synthesized)
- `LocalTypelessTests/Fixtures/zh_hello.wav` — 2–3s Chinese fixture
- `LocalTypelessTests/WhisperKitASRServiceTests.swift` — integration test (skippable via env flag)
- `LocalTypelessTests/ModelStatusStoreTests.swift` — unit test for the store

**Modify:**
- `project.yml` — add `WhisperKit` Swift package dependency, add fixture resources to test target
- `LocalTypeless/Core/AudioBuffer.swift` — mark `@unchecked Sendable`, add `snapshot() -> [Float]` accessor
- `LocalTypeless/Services/ASRService.swift` — mark protocols `Sendable` where sensible
- `LocalTypeless/Services/PolishService.swift` — same
- `LocalTypeless/App/AppDelegate.swift` — wire `ModelManager` + `ModelStatusStore`; gate `handleToggle` on ASR-readiness; open download sheet when not ready; add pipeline timeout; surface store-open failure via alert instead of `fatalError`; call `unloadModels()` into the real manager
- `LocalTypeless/App/MenuBarController.swift` — reflect model status in tooltip + menu ("Download model…", "Unload ASR model")
- `LocalTypeless/Services/TextInjector.swift` — extend pasteboard-restore delay to 300 ms and restore via completion rather than fixed sleep where practical

---

## Task 0: Phase 1 cleanup (prep before Phase 2)

**Files:**
- Modify: `LocalTypeless/Core/AudioBuffer.swift`
- Modify: `LocalTypeless/Services/ASRService.swift`
- Modify: `LocalTypeless/Services/PolishService.swift`
- Modify: `LocalTypeless/Services/TextInjector.swift`
- Modify: `LocalTypeless/App/AppDelegate.swift`
- Create: `LocalTypeless/Support/PipelineTimeout.swift`

- [ ] **Step 0.1: Make `AudioBuffer` `@unchecked Sendable` and add a snapshot accessor**

Edit `LocalTypeless/Core/AudioBuffer.swift`:

```swift
import Foundation

final class AudioBuffer: @unchecked Sendable {
    let sampleRate: Double
    let maxSeconds: Double
    private var samples: [Float] = []
    private let lock = NSLock()

    init(maxSeconds: Double, sampleRate: Double) {
        self.maxSeconds = maxSeconds
        self.sampleRate = sampleRate
    }

    func append(_ chunk: [Float]) {
        lock.lock(); defer { lock.unlock() }
        samples.append(contentsOf: chunk)
        let cap = Int(maxSeconds * sampleRate)
        if samples.count > cap {
            samples.removeFirst(samples.count - cap)
        }
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
    }

    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return samples.count
    }

    var durationSeconds: Double {
        Double(count) / sampleRate
    }
}
```

- [ ] **Step 0.2: Mark service protocols `Sendable`**

Edit `LocalTypeless/Services/ASRService.swift` — change `protocol ASRService: AnyObject` to `protocol ASRService: AnyObject, Sendable` and make `Transcript` and `Transcript.Segment` conform to `Sendable` (they're value types of `Sendable` members, so just add `Sendable` to the declaration).

Edit `LocalTypeless/Services/PolishService.swift` — change `protocol PolishService: AnyObject` to `protocol PolishService: AnyObject, Sendable`.

- [ ] **Step 0.3: Add a pipeline timeout helper**

Create `LocalTypeless/Support/PipelineTimeout.swift`:

```swift
import Foundation

enum PipelineTimeoutError: Error { case timedOut }

func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw PipelineTimeoutError.timedOut
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

- [ ] **Step 0.4: Lengthen `TextInjector` pasteboard restore delay to 300 ms**

In `LocalTypeless/Services/TextInjector.swift`, find the `Task.sleep(nanoseconds: 150_000_000)` (or equivalent) and change to `300_000_000`. If the sleep is expressed as `150 * .millisecond` or similar, update accordingly. Add a comment: `// wait for the target app to consume Cmd+V before restoring`.

- [ ] **Step 0.5: Surface history-store open failures via alert instead of `fatalError`**

In `LocalTypeless/App/AppDelegate.swift`, change `makeHistoryStore()` to return `HistoryStore?` (Optional):

```swift
private static func makeHistoryStore() -> HistoryStore? {
    let supportDir = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
        .appendingPathComponent("local-typeless", isDirectory: true)
    let dbURL = supportDir.appendingPathComponent("history.sqlite")
    do {
        return try SQLiteHistoryStore(path: dbURL)
    } catch {
        Log.state.error("history store open failed: \(String(describing: error), privacy: .public)")
        return nil
    }
}
```

Change the property to `private var historyStore: HistoryStore?` and update `applicationDidFinishLaunching` to show an NSAlert when `historyStore == nil`:

```swift
historyStore = Self.makeHistoryStore()
if historyStore == nil {
    let alert = NSAlert()
    alert.messageText = "Could not open history database"
    alert.informativeText = "Dictation will still work, but transcripts won't be saved to history."
    alert.alertStyle = .warning
    alert.runModal()
}
```

Update `runPipeline()` to guard: `if let store = historyStore { try? store.insert(entry) }`.

- [ ] **Step 0.6: Wrap the pipeline in a 60-second timeout**

In `runPipeline()`, change the ASR call from:

```swift
transcript = try await asrService.transcribe(audioBuffer)
```

to:

```swift
transcript = try await withTimeout(60) { [asrService, audioBuffer] in
    try await asrService.transcribe(audioBuffer)
}
```

And similarly wrap the polish call with `withTimeout(30)`. On `PipelineTimeoutError.timedOut`, fail gracefully: for ASR, call `stateMachine.fail(message: "Transcription timed out")` and return; for polish, fall back to raw transcript (same as existing error path).

- [ ] **Step 0.7: Run tests, commit**

Run: `xcodegen generate && xcodebuild test -scheme LocalTypeless -destination 'platform=macOS' 2>&1 | tail -40`
Expected: all 27 existing tests pass; no new warnings from strict-concurrency.

```bash
git add -A
git commit -m "chore: Phase 2 prep — Sendable + pipeline timeout + error surfacing"
```

---

## Task 1: Add WhisperKit Swift package dependency

**Files:**
- Modify: `project.yml`

- [ ] **Step 1.1: Add the package**

Edit `project.yml` — add to the `packages:` block:

```yaml
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: 6.29.0
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit
    from: 0.13.0
```

Under `targets: LocalTypeless: dependencies:`, add:

```yaml
    dependencies:
      - package: GRDB
      - package: WhisperKit
```

- [ ] **Step 1.2: Regenerate and verify resolution**

Run: `xcodegen generate && xcodebuild -resolvePackageDependencies -scheme LocalTypeless 2>&1 | tail -20`
Expected: `WhisperKit` and its transitive deps (`swift-transformers`, etc.) resolve successfully.

- [ ] **Step 1.3: Build, commit**

Run: `xcodebuild build -scheme LocalTypeless -destination 'platform=macOS' 2>&1 | tail -20`
Expected: build succeeds (no code using WhisperKit yet).

```bash
git add project.yml LocalTypeless.xcodeproj
git commit -m "feat: add WhisperKit Swift package dependency"
```

---

## Task 2: ModelStatus types (TDD)

**Files:**
- Create: `LocalTypeless/Services/Models/ModelStatus.swift`
- Create: `LocalTypelessTests/ModelStatusStoreTests.swift`
- Create: `LocalTypeless/Services/Models/ModelStatusStore.swift`

- [ ] **Step 2.1: Write the failing test**

Create `LocalTypelessTests/ModelStatusStoreTests.swift`:

```swift
import XCTest
@testable import LocalTypeless

@MainActor
final class ModelStatusStoreTests: XCTestCase {

    func test_defaults_to_not_downloaded() {
        let store = ModelStatusStore()
        XCTAssertEqual(store.status(for: .asrWhisperLargeV3Turbo), .notDownloaded)
    }

    func test_set_updates_status() {
        let store = ModelStatusStore()
        store.set(.downloading(progress: 0.42), for: .asrWhisperLargeV3Turbo)
        if case .downloading(let p) = store.status(for: .asrWhisperLargeV3Turbo) {
            XCTAssertEqual(p, 0.42, accuracy: 0.001)
        } else {
            XCTFail("expected .downloading")
        }
    }

    func test_is_ready_reflects_resident() {
        let store = ModelStatusStore()
        XCTAssertFalse(store.isReady(.asrWhisperLargeV3Turbo))
        store.set(.resident, for: .asrWhisperLargeV3Turbo)
        XCTAssertTrue(store.isReady(.asrWhisperLargeV3Turbo))
    }

    func test_downloaded_is_not_ready_until_loaded() {
        let store = ModelStatusStore()
        store.set(.downloaded, for: .asrWhisperLargeV3Turbo)
        XCTAssertFalse(store.isReady(.asrWhisperLargeV3Turbo))
    }
}
```

- [ ] **Step 2.2: Run test to verify it fails**

Run: `xcodebuild test -scheme LocalTypeless -destination 'platform=macOS' -only-testing:LocalTypelessTests/ModelStatusStoreTests 2>&1 | tail -20`
Expected: compile failure (`ModelStatusStore` undefined).

- [ ] **Step 2.3: Implement ModelStatus**

Create `LocalTypeless/Services/Models/ModelStatus.swift`:

```swift
import Foundation

enum ModelKind: String, Sendable, Hashable, CaseIterable {
    case asrWhisperLargeV3Turbo
    case polishQwen25_3bInstruct4bit
}

enum ModelStatus: Sendable, Equatable {
    case notDownloaded
    case downloading(progress: Double)  // 0.0 ... 1.0
    case downloaded                      // on disk, not loaded into RAM
    case loading                         // loading into memory
    case resident                        // loaded and ready
    case failed(message: String)
}
```

- [ ] **Step 2.4: Implement ModelStatusStore**

Create `LocalTypeless/Services/Models/ModelStatusStore.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class ModelStatusStore {
    private var statuses: [ModelKind: ModelStatus] = [:]

    func status(for kind: ModelKind) -> ModelStatus {
        statuses[kind] ?? .notDownloaded
    }

    func set(_ status: ModelStatus, for kind: ModelKind) {
        statuses[kind] = status
    }

    func isReady(_ kind: ModelKind) -> Bool {
        if case .resident = status(for: kind) { return true }
        return false
    }
}
```

- [ ] **Step 2.5: Run test to verify pass**

Run: `xcodebuild test -scheme LocalTypeless -destination 'platform=macOS' -only-testing:LocalTypelessTests/ModelStatusStoreTests 2>&1 | tail -10`
Expected: 4/4 pass.

- [ ] **Step 2.6: Commit**

```bash
git add LocalTypeless/Services/Models LocalTypelessTests/ModelStatusStoreTests.swift
git commit -m "feat: add ModelStatus types and @Observable ModelStatusStore"
```

---

## Task 3: ModelManager protocol + WhisperKit concrete

**Files:**
- Create: `LocalTypeless/Services/Models/ModelManager.swift`

- [ ] **Step 3.1: Define the protocol and concrete manager**

Create `LocalTypeless/Services/Models/ModelManager.swift`:

```swift
import Foundation
import WhisperKit

protocol ModelManager: AnyObject, Sendable {
    /// Ensure the given model is downloaded AND loaded in RAM.
    /// Publishes progress via the injected store.
    func ensureReady(_ kind: ModelKind) async throws

    /// Release the model from RAM (if loaded). Files on disk are retained.
    func unload(_ kind: ModelKind) async

    /// Read-only access to the underlying WhisperKit instance (nil if not resident).
    var whisperKit: WhisperKit? { get async }
}

enum ModelManagerError: LocalizedError {
    case unsupportedKind(ModelKind)
    case initializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedKind(let k): return "Model kind \(k.rawValue) not supported by this manager"
        case .initializationFailed(let m): return "Model initialization failed: \(m)"
        }
    }
}

actor WhisperKitModelManager: ModelManager {

    private let store: ModelStatusStore
    private var kit: WhisperKit?
    private let modelVariant = "openai_whisper-large-v3-turbo"

    init(store: ModelStatusStore) {
        self.store = store
    }

    var whisperKit: WhisperKit? { kit }

    func ensureReady(_ kind: ModelKind) async throws {
        guard kind == .asrWhisperLargeV3Turbo else {
            throw ModelManagerError.unsupportedKind(kind)
        }
        if kit != nil {
            await MainActor.run { store.set(.resident, for: kind) }
            return
        }

        await MainActor.run { store.set(.loading, for: kind) }

        do {
            // WhisperKit's default init downloads and loads the model.
            // Progress is approximate; WhisperKit reports only coarse phases.
            let config = WhisperKitConfig(
                model: modelVariant,
                downloadBase: nil,
                modelRepo: "argmaxinc/whisperkit-coreml",
                verbose: false,
                logLevel: .info,
                prewarm: true,
                load: true,
                download: true
            )
            let wk = try await WhisperKit(config)
            self.kit = wk
            await MainActor.run { store.set(.resident, for: kind) }
        } catch {
            await MainActor.run {
                store.set(.failed(message: error.localizedDescription), for: kind)
            }
            throw ModelManagerError.initializationFailed(error.localizedDescription)
        }
    }

    func unload(_ kind: ModelKind) async {
        guard kind == .asrWhisperLargeV3Turbo else { return }
        kit = nil
        await MainActor.run { store.set(.downloaded, for: kind) }
    }
}
```

Note: WhisperKit's public API as of 0.13 does not expose fine-grained download progress callbacks. For Phase 2, we accept coarse progress (notDownloaded → loading → resident). A Phase 6 follow-up can replace this with the lower-level `WhisperKit.download(variant:from:progressCallback:)` API once stable.

- [ ] **Step 3.2: Verify build**

Run: `xcodebuild build -scheme LocalTypeless -destination 'platform=macOS' 2>&1 | tail -20`
Expected: build succeeds; no warnings on `@Observable` or actor isolation.

- [ ] **Step 3.3: Commit**

```bash
git add LocalTypeless/Services/Models/ModelManager.swift
git commit -m "feat: add ModelManager protocol with WhisperKit-backed implementation"
```

---

## Task 4: WhisperKitASRService

**Files:**
- Create: `LocalTypeless/Services/WhisperKitASRService.swift`

- [ ] **Step 4.1: Implement the service**

Create `LocalTypeless/Services/WhisperKitASRService.swift`:

```swift
import Foundation
import WhisperKit

enum WhisperKitASRError: LocalizedError {
    case modelNotReady
    case emptyAudio
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady: return "ASR model is not loaded"
        case .emptyAudio: return "No audio captured"
        case .transcriptionFailed(let m): return "Transcription failed: \(m)"
        }
    }
}

/// Language mode the user can force. `nil` means auto-detect.
struct ASROptions: Sendable {
    var forcedLanguage: String?  // BCP-47 ("en", "zh") — nil = auto
    static let auto = ASROptions(forcedLanguage: nil)
}

final class WhisperKitASRService: ASRService, @unchecked Sendable {

    private let manager: ModelManager
    private let options: ASROptions

    init(manager: ModelManager, options: ASROptions = .auto) {
        self.manager = manager
        self.options = options
    }

    func transcribe(_ audio: AudioBuffer) async throws -> Transcript {
        let samples = audio.snapshot()
        guard !samples.isEmpty else { throw WhisperKitASRError.emptyAudio }

        // Ensure the model is ready (idempotent if already loaded).
        try await manager.ensureReady(.asrWhisperLargeV3Turbo)
        guard let kit = await manager.whisperKit else {
            throw WhisperKitASRError.modelNotReady
        }

        do {
            let decodeOptions = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: options.forcedLanguage,  // nil → auto-detect
                temperature: 0.0,
                usePrefillPrompt: true,
                skipSpecialTokens: true,
                withoutTimestamps: false
            )

            let results = try await kit.transcribe(audioArray: samples,
                                                   decodeOptions: decodeOptions)
            let first = results.first
            let text = first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lang = first?.language ?? options.forcedLanguage ?? "en"
            let segs: [Transcript.Segment] = (first?.segments ?? []).map {
                Transcript.Segment(
                    text: $0.text,
                    startSeconds: Double($0.start),
                    endSeconds: Double($0.end)
                )
            }
            return Transcript(text: text, language: lang, segments: segs)
        } catch {
            throw WhisperKitASRError.transcriptionFailed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4.2: Verify build**

Run: `xcodebuild build -scheme LocalTypeless -destination 'platform=macOS' 2>&1 | tail -30`
Expected: build succeeds. If WhisperKit's API signatures differ (e.g. `results` is `[TranscriptionResult]` not optional, or segments type naming differs), adjust the adapter using WhisperKit's current types — Sonnet: consult the package source under `.build/checkouts/WhisperKit/Sources/` if in doubt; the types we rely on are `WhisperKit`, `WhisperKitConfig`, `DecodingOptions`, `TranscriptionResult`.

- [ ] **Step 4.3: Commit**

```bash
git add LocalTypeless/Services/WhisperKitASRService.swift
git commit -m "feat: add WhisperKitASRService adapting WhisperKit to ASRService protocol"
```

---

## Task 5: Integration test with audio fixtures

**Files:**
- Create: `LocalTypelessTests/Fixtures/en_hello.wav`
- Create: `LocalTypelessTests/Fixtures/zh_hello.wav`
- Create: `LocalTypelessTests/WhisperKitASRServiceTests.swift`
- Modify: `project.yml`

- [ ] **Step 5.1: Generate fixture audio**

Fixtures must be 16 kHz, 16-bit PCM, mono, 2–3 seconds. Prefer recording with the built-in mic if a microphone is available; otherwise use macOS's `say` command:

```bash
mkdir -p LocalTypelessTests/Fixtures
say -v Samantha -o LocalTypelessTests/Fixtures/en_hello.aiff "Hello, this is a dictation test."
afconvert LocalTypelessTests/Fixtures/en_hello.aiff \
    LocalTypelessTests/Fixtures/en_hello.wav \
    -d LEI16@16000 -c 1 -f WAVE
rm LocalTypelessTests/Fixtures/en_hello.aiff

say -v "Tingting" -o LocalTypelessTests/Fixtures/zh_hello.aiff "你好，这是一个听写测试。"
afconvert LocalTypelessTests/Fixtures/zh_hello.aiff \
    LocalTypelessTests/Fixtures/zh_hello.wav \
    -d LEI16@16000 -c 1 -f WAVE
rm LocalTypelessTests/Fixtures/zh_hello.aiff
```

If the `Tingting` voice isn't installed, substitute any Chinese voice from `say -v '?' | grep zh`. If none available, skip the ZH fixture and mark the ZH test `throws XCTSkip`.

- [ ] **Step 5.2: Wire fixtures as test resources**

In `project.yml`, under `targets: LocalTypelessTests:`, add:

```yaml
    resources:
      - path: LocalTypelessTests/Fixtures
```

Run `xcodegen generate` to regenerate the project.

- [ ] **Step 5.3: Write the integration test**

Create `LocalTypelessTests/WhisperKitASRServiceTests.swift`:

```swift
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
```

- [ ] **Step 5.4: Run the integration test**

These tests download ~1.5 GB on first run. Expect first run to take minutes.

Run: `xcodebuild test -scheme LocalTypeless -destination 'platform=macOS' -only-testing:LocalTypelessTests/WhisperKitASRServiceTests 2>&1 | tail -30`
Expected on first run: downloads model, tests pass. On subsequent runs: <30 seconds.

- [ ] **Step 5.5: Commit**

```bash
git add LocalTypelessTests/Fixtures LocalTypelessTests/WhisperKitASRServiceTests.swift project.yml LocalTypeless.xcodeproj
git commit -m "test: add WhisperKit ASR integration tests with EN+ZH audio fixtures"
```

---

## Task 6: Model download sheet UI

**Files:**
- Create: `LocalTypeless/UI/ModelDownloadView.swift`

- [ ] **Step 6.1: Implement the view**

Create `LocalTypeless/UI/ModelDownloadView.swift`:

```swift
import SwiftUI

struct ModelDownloadView: View {
    @Bindable var store: ModelStatusStore
    let onStart: () -> Void
    let onCancel: () -> Void

    private let kind: ModelKind = .asrWhisperLargeV3Turbo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "waveform")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Download speech model")
                        .font(.headline)
                    Text("~1.5 GB · offline after download")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            statusRow

            Spacer(minLength: 12)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                actionButton
            }
        }
        .padding(24)
        .frame(width: 420, height: 220)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch store.status(for: kind) {
        case .notDownloaded:
            Label("Not downloaded yet", systemImage: "arrow.down.circle")
        case .downloading(let p):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: p)
                Text("Downloading… \(Int(p * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .downloaded:
            Label("Downloaded (not loaded)", systemImage: "externaldrive.fill.badge.checkmark")
        case .loading:
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading into memory…")
            }
        case .resident:
            Label("Ready", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch store.status(for: kind) {
        case .notDownloaded, .failed:
            Button("Download", action: onStart)
                .keyboardShortcut(.defaultAction)
        case .downloading, .loading:
            Button("Working…") {}.disabled(true)
        case .downloaded:
            Button("Load", action: onStart)
                .keyboardShortcut(.defaultAction)
        case .resident:
            Button("Done", action: onCancel)
                .keyboardShortcut(.defaultAction)
        }
    }
}
```

- [ ] **Step 6.2: Verify build**

Run: `xcodebuild build -scheme LocalTypeless -destination 'platform=macOS' 2>&1 | tail -10`
Expected: success.

- [ ] **Step 6.3: Commit**

```bash
git add LocalTypeless/UI/ModelDownloadView.swift
git commit -m "feat: add ModelDownloadView sheet with per-status actions"
```

---

## Task 7: Wire AppDelegate gating

**Files:**
- Modify: `LocalTypeless/App/AppDelegate.swift`

- [ ] **Step 7.1: Replace stubs with real services and add gating**

In `LocalTypeless/App/AppDelegate.swift`:

Add new properties:

```swift
    private var modelManager: ModelManager!
    private var modelStatusStore: ModelStatusStore!
    private var modelDownloadWindow: NSWindow?
```

In `applicationDidFinishLaunching`, replace the stub service setup:

```swift
        modelStatusStore = ModelStatusStore()
        modelManager = WhisperKitModelManager(store: modelStatusStore)
        asrService = WhisperKitASRService(manager: modelManager)
        polishService = StubPolishService()  // Phase 3 will replace
```

Replace `handleToggle()`:

```swift
    private func handleToggle() {
        if !modelStatusStore.isReady(.asrWhisperLargeV3Turbo) {
            openModelDownload()
            return
        }
        switch stateMachine.state {
        case .idle:
            captureFocusedApp()
            do {
                try recorder.start()
                recordingStart = Date()
                stateMachine.toggle()
            } catch {
                Log.recorder.error("start failed: \(String(describing: error), privacy: .public)")
                stateMachine.fail(message: "Recording failed")
            }
        case .recording:
            recorder.stop()
            stateMachine.toggle()
            Task { await runPipeline() }
        case .error:
            stateMachine.toggle()
        default:
            break
        }
    }
```

Add:

```swift
    private func openModelDownload() {
        if let w = modelDownloadWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let view = ModelDownloadView(
            store: modelStatusStore,
            onStart: { [weak self] in self?.startModelDownload() },
            onCancel: { [weak self] in self?.modelDownloadWindow?.close() }
        )
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Model Setup"
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        modelDownloadWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func startModelDownload() {
        Task { [modelManager, modelStatusStore] in
            do {
                try await modelManager!.ensureReady(.asrWhisperLargeV3Turbo)
            } catch {
                await MainActor.run {
                    modelStatusStore!.set(.failed(message: error.localizedDescription),
                                          for: .asrWhisperLargeV3Turbo)
                }
            }
        }
    }
```

Replace `unloadModels()`:

```swift
    private func unloadModels() {
        Task { [modelManager] in
            await modelManager!.unload(.asrWhisperLargeV3Turbo)
        }
    }
```

- [ ] **Step 7.2: Build**

Run: `xcodebuild build -scheme LocalTypeless -destination 'platform=macOS' 2>&1 | tail -20`
Expected: success.

- [ ] **Step 7.3: Commit**

```bash
git add LocalTypeless/App/AppDelegate.swift
git commit -m "feat: gate dictation pipeline on ASR model readiness and wire download sheet"
```

---

## Task 8: MenuBarController reflects model status

**Files:**
- Modify: `LocalTypeless/App/MenuBarController.swift`

- [ ] **Step 8.1: Inject the store and show a status line**

Extend `MenuBarController` to accept a `ModelStatusStore`:

```swift
init(stateMachine: StateMachine,
     modelStatusStore: ModelStatusStore,
     onOpenSettings: @escaping () -> Void,
     onOpenHistory: @escaping () -> Void,
     onUnloadModels: @escaping () -> Void,
     onOpenModelDownload: @escaping () -> Void) { ... }
```

Store these new closures. In `rebuildMenu()` (or whatever the existing menu builder is called), add:

```swift
let asrStatus = modelStatusStore.status(for: .asrWhisperLargeV3Turbo)
let statusTitle: String
switch asrStatus {
case .notDownloaded:           statusTitle = "ASR model: Not downloaded"
case .downloading(let p):      statusTitle = "ASR model: Downloading (\(Int(p*100))%)"
case .downloaded:              statusTitle = "ASR model: Downloaded (not loaded)"
case .loading:                 statusTitle = "ASR model: Loading…"
case .resident:                statusTitle = "ASR model: Ready"
case .failed(let m):           statusTitle = "ASR model: Failed — \(m)"
}
let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
statusItem.isEnabled = false
menu.addItem(statusItem)

if case .resident = asrStatus { /* unload stays */ } else {
    let download = NSMenuItem(title: "Download ASR model…",
                              action: #selector(openModelDownloadAction),
                              keyEquivalent: "")
    download.target = self
    menu.addItem(download)
}
```

Add `@objc private func openModelDownloadAction() { onOpenModelDownload() }`.

Extend the existing `withObservationTracking` block (or its equivalent) so that changes to `modelStatusStore.statuses` also trigger a re-render. The simplest form:

```swift
withObservationTracking {
    _ = stateMachine.state
    _ = modelStatusStore.status(for: .asrWhisperLargeV3Turbo)
} onChange: { [weak self] in
    Task { @MainActor in self?.refresh() }
}
```

- [ ] **Step 8.2: Update `AppDelegate` call site**

In `applicationDidFinishLaunching`, pass the new arguments:

```swift
menuBarController = MenuBarController(
    stateMachine: stateMachine,
    modelStatusStore: modelStatusStore,
    onOpenSettings: { [weak self] in self?.openSettings() },
    onOpenHistory: { [weak self] in self?.openHistory() },
    onUnloadModels: { [weak self] in self?.unloadModels() },
    onOpenModelDownload: { [weak self] in self?.openModelDownload() }
)
```

- [ ] **Step 8.3: Build**

Run: `xcodebuild build -scheme LocalTypeless -destination 'platform=macOS' 2>&1 | tail -10`
Expected: success.

- [ ] **Step 8.4: Commit**

```bash
git add LocalTypeless/App/MenuBarController.swift LocalTypeless/App/AppDelegate.swift
git commit -m "feat: surface ASR model status in menu-bar dropdown"
```

---

## Task 9: Final phase review and tag

- [ ] **Step 9.1: Run the full test suite**

Run: `xcodebuild test -scheme LocalTypeless -destination 'platform=macOS' 2>&1 | tail -20`
Expected: all Phase 1 tests + ModelStatusStoreTests pass. WhisperKitASRServiceTests may be skipped if `LOCAL_TYPELESS_SKIP_MODEL_TESTS=1` is set; otherwise they should pass (after model download).

- [ ] **Step 9.2: Manual smoke test**

```bash
make run
```

- First click on hotkey → model download sheet appears
- Click Download → progress fills in; ends with "Ready"
- Close sheet
- Click hotkey in TextEdit → speaks → click again → English appears in TextEdit
- Click hotkey in TextEdit → speaks Chinese → click again → 中文 appears in TextEdit
- Menu shows "ASR model: Ready"; "Unload ASR model" works

Document any issues for Phase 6 follow-up.

- [ ] **Step 9.3: Tag**

```bash
git tag phase-2-complete
```

---

## Self-review checklist (run before dispatching Task 0)

- **Spec coverage:** Phase 2 goals from spec §5.3 and §7 — WhisperKit integration, language auto-detect, model download onboarding — are all covered across Tasks 1–9.
- **Placeholders:** No TBD / TODO entries. WhisperKit API types referenced (`WhisperKitConfig`, `DecodingOptions`, `TranscriptionResult`) may have version-specific naming — Task 4 explicitly authorizes Sonnet to adjust if the current package exposes different names.
- **Type consistency:** `ModelKind` used identically across Tasks 2, 3, 7, 8. `ModelStatus` cases match between the enum (Task 2) and the switches in Tasks 6/8.
- **Review notes folded in:** Task 0 addresses all four low-priority review items identified after Phase 1 (Sendable, timeout, pasteboard delay, fatalError → alert).
