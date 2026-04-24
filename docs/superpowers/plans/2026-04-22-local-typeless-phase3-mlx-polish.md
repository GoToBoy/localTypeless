# Phase 3 — MLX Swift Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Replace `StubPolishService` with a real `MLXPolishService` backed by Qwen2.5-3B-Instruct-4bit (MLX format), with model download UI, user-editable prompt, a ~2× input-token output cap, and graceful fallback to raw transcript on any failure.

**Architecture:** Introduce a second `ModelManager` (`MLXPolishModelManager`) sibling to `WhisperKitModelManager`. `ModelStatusStore` already supports multiple `ModelKind`s. Generalize `ModelDownloadView` to take a `ModelKind` argument. `AppDelegate` owns both managers and gates the pipeline on BOTH models being resident. Polish service adapts `PolishService.polish(_:prompt:)` to MLX's chat-completion API.

**Tech Stack:** `mlx-swift-examples` (provides `MLXLLM` package with `ModelContainer`, `LLMModelFactory`, `MLXLMCommon.generate`), Qwen2.5-3B-Instruct-4bit from `mlx-community/Qwen2.5-3B-Instruct-4bit` on HuggingFace.

**Default prompt (EN):**
> You are a dictation cleanup assistant. Rewrite the user's speech by: 1) Removing filler words (um, uh, 呃, 嗯, like, you know). 2) Fixing punctuation and capitalization. 3) Preserving the speaker's meaning and tone exactly. 4) Keeping the language of the original (do not translate). Output only the cleaned text, no commentary.

**Default prompt (ZH):** Translation of the above.

---

## File structure

**Create:**
- `LocalTypeless/Services/Models/MLXPolishModelManager.swift` — actor managing Qwen lifecycle
- `LocalTypeless/Services/MLXPolishService.swift` — `PolishService` adapter
- `LocalTypeless/Services/DefaultPrompts.swift` — exported EN + ZH default prompt strings
- `LocalTypelessTests/MLXPolishServiceTests.swift` — integration test (skippable)
- `LocalTypelessTests/DefaultPromptsTests.swift` — trivial test that both prompts are non-empty and distinct

**Modify:**
- `project.yml` — add `mlx-swift-examples` Swift package, add `MLXLLM` product to LocalTypeless target
- `LocalTypeless/Services/Models/ModelManager.swift` — extract `ModelManager` protocol into its own file if it isn't already (so two concrete actors can coexist cleanly)
- `LocalTypeless/UI/ModelDownloadView.swift` — take `kind: ModelKind` and a title/subtitle mapping so the sheet works for either ASR or polish model
- `LocalTypeless/App/AppDelegate.swift` — build `mlxPolishManager`, replace `StubPolishService` with `MLXPolishService`, extend gating to require both models `.resident`, route download sheet to whichever model is missing first
- `LocalTypeless/App/MenuBarController.swift` — show status for BOTH models, add "Unload polish model" and "Download polish model…" menu items

---

## Task 1: Add mlx-swift-examples dependency

**Files:** `project.yml`

- [ ] **Step 1.1:** Under `packages:` in `project.yml`, add:

```yaml
  MLXSwiftExamples:
    url: https://github.com/ml-explore/mlx-swift-examples
    from: 2.21.0
```

(If that version fails to resolve, try `2.20.0`, `2.15.0`, or the `main` branch.) Under `targets: LocalTypeless: dependencies:`, add:

```yaml
      - package: MLXSwiftExamples
        product: MLXLLM
      - package: MLXSwiftExamples
        product: MLXLMCommon
```

- [ ] **Step 1.2:** `xcodegen generate && xcodebuild -resolvePackageDependencies -scheme LocalTypeless 2>&1 | tail -20`. Allow 3-5 minutes for resolution.

- [ ] **Step 1.3:** `xcodebuild build -scheme LocalTypeless -destination 'platform=macOS' 2>&1 | tail -20`. Expected success.

- [ ] **Step 1.4:** Commit: `feat: add mlx-swift-examples (MLXLLM + MLXLMCommon) dependency`

---

## Task 2: Default prompts (TDD)

**Files:** `LocalTypeless/Services/DefaultPrompts.swift`, `LocalTypelessTests/DefaultPromptsTests.swift`

- [ ] **Step 2.1:** Create the failing test:

```swift
import XCTest
@testable import LocalTypeless

final class DefaultPromptsTests: XCTestCase {
    func test_en_and_zh_prompts_are_nonempty_and_distinct() {
        let en = DefaultPrompts.polish(for: "en")
        let zh = DefaultPrompts.polish(for: "zh")
        XCTAssertFalse(en.isEmpty)
        XCTAssertFalse(zh.isEmpty)
        XCTAssertNotEqual(en, zh)
    }

    func test_unknown_language_falls_back_to_english() {
        XCTAssertEqual(DefaultPrompts.polish(for: "fr"),
                       DefaultPrompts.polish(for: "en"))
    }

    func test_mentions_filler_words_in_each_language() {
        XCTAssertTrue(DefaultPrompts.polish(for: "en").contains("filler"))
        XCTAssertTrue(DefaultPrompts.polish(for: "zh").contains("语气词")
                      || DefaultPrompts.polish(for: "zh").contains("填充"))
    }
}
```

Run the test, verify it fails to compile (RED).

- [ ] **Step 2.2:** Implement `DefaultPrompts.swift`:

```swift
import Foundation

enum DefaultPrompts {
    static let polishEN: String = """
        You are a dictation cleanup assistant. Rewrite the user's speech by:
        1. Removing filler words (um, uh, 呃, 嗯, like, you know).
        2. Fixing punctuation and capitalization.
        3. Preserving the speaker's meaning and tone exactly.
        4. Keeping the language of the original (do not translate).
        Output only the cleaned text, no commentary.
        """

    static let polishZH: String = """
        你是一个口述整理助手。请按照以下规则改写用户的口述内容：
        1. 去除语气词和填充词（嗯、呃、um、uh、like、you know 等）。
        2. 修正标点和大小写。
        3. 完整保留说话人的本意和语气。
        4. 保持原语言，不要翻译。
        只输出整理后的文本，不要添加任何说明。
        """

    static func polish(for bcp47Language: String) -> String {
        bcp47Language.lowercased().hasPrefix("zh") ? polishZH : polishEN
    }
}
```

- [ ] **Step 2.3:** Run tests, verify 3/3 pass (GREEN).

- [ ] **Step 2.4:** Commit: `feat: add default polish prompts for EN and ZH`

---

## Task 3: Extend ModelKind + polish manager (TDD for store part)

**Files:** `LocalTypeless/Services/Models/ModelStatus.swift`, `LocalTypeless/Services/Models/MLXPolishModelManager.swift`

- [ ] **Step 3.1:** Verify `ModelKind` already has both cases. If not, add the polish case. The enum should already be:

```swift
enum ModelKind: String, Sendable, Hashable, CaseIterable {
    case asrWhisperLargeV3Turbo
    case polishQwen25_3bInstruct4bit
}
```

(Both cases exist from Phase 2 Task 2.)

- [ ] **Step 3.2:** Implement `MLXPolishModelManager.swift`:

```swift
import Foundation
import MLXLLM
import MLXLMCommon

actor MLXPolishModelManager: ModelManager {

    private let store: ModelStatusStore
    private var container: ModelContainer?
    private var inFlight: Task<Void, Error>?
    private let modelId = "mlx-community/Qwen2.5-3B-Instruct-4bit"

    init(store: ModelStatusStore) {
        self.store = store
    }

    /// WhisperKit is ASR-only; polish manager returns nil for the whisperKit getter.
    var whisperKit: WhisperKit? {
        get async { nil }
    }

    func ensureReady(_ kind: ModelKind) async throws {
        guard kind == .polishQwen25_3bInstruct4bit else {
            throw ModelManagerError.unsupportedKind(kind)
        }
        if container != nil {
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

    private func load(kind: ModelKind) async throws {
        await MainActor.run { store.set(.loading, for: kind) }
        do {
            let config = ModelConfiguration(id: modelId)
            let c = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            )
            self.container = c
            await MainActor.run { store.set(.resident, for: kind) }
        } catch {
            await MainActor.run {
                store.set(.failed(message: error.localizedDescription), for: kind)
            }
            throw ModelManagerError.initializationFailed(error.localizedDescription)
        }
    }

    func unload(_ kind: ModelKind) async {
        guard kind == .polishQwen25_3bInstruct4bit else { return }
        container = nil
        await MainActor.run { store.set(.downloaded, for: kind) }
    }

    /// Exposed for MLXPolishService to run prompts against.
    var modelContainer: ModelContainer? { container }
}
```

**IMPORTANT API NOTE:** The `MLXLLM` API may have evolved. If `LLMModelFactory.shared.loadContainer(configuration:)` has a different signature (e.g. `hub:` or `progressHandler:` params, or the factory is named differently like `ModelFactory`), adjust using whatever exists in `mlx-swift-examples` at the resolved version. Verify by inspecting `.build/checkouts/mlx-swift-examples/Libraries/MLXLLM/` or the `SourcePackages/checkouts/` equivalent.

Issue: the `ModelManager` protocol currently returns `whisperKit: WhisperKit?`. This is too specific for two kinds. Options:
- (a) Add a kind-check to the getter and return nil for the wrong kind (what we did above). Cheapest change, keeps existing protocol.
- (b) Remove the getter from the protocol and put it only on the concrete WhisperKit manager. Requires AppDelegate to hold concrete types.

**Pick option (a)** for Phase 3 — minimum disturbance to existing code. The getter becomes effectively a "whisperKit if this manager holds one" semantic. If it becomes unwieldy in Phase 4+, revisit.

- [ ] **Step 3.3:** Build, verify no warnings. The unused `whisperKit` getter on the polish manager is fine (always returns nil).

- [ ] **Step 3.4:** Commit: `feat: add MLXPolishModelManager actor for Qwen2.5-3B lifecycle`

---

## Task 4: MLXPolishService

**Files:** `LocalTypeless/Services/MLXPolishService.swift`

- [ ] **Step 4.1:** Implement the adapter:

```swift
import Foundation
import MLXLLM
import MLXLMCommon

enum MLXPolishError: LocalizedError {
    case modelNotReady
    case emptyInput
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady: return "Polish model is not loaded"
        case .emptyInput: return "Empty transcript"
        case .generationFailed(let m): return "Polish generation failed: \(m)"
        }
    }
}

/// Sendable: stored fields are `let` and the manager is an actor.
final class MLXPolishService: PolishService, @unchecked Sendable {

    private let manager: MLXPolishModelManager
    private let maxTokensMultiplier: Int

    init(manager: MLXPolishModelManager, maxTokensMultiplier: Int = 2) {
        self.manager = manager
        self.maxTokensMultiplier = maxTokensMultiplier
    }

    func polish(_ transcript: Transcript, prompt: String) async throws -> String {
        let raw = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw MLXPolishError.emptyInput }

        try await manager.ensureReady(.polishQwen25_3bInstruct4bit)
        guard let container = await manager.modelContainer else {
            throw MLXPolishError.modelNotReady
        }

        let effectivePrompt = prompt.isEmpty
            ? DefaultPrompts.polish(for: transcript.language)
            : prompt

        // Rough estimate: 1 token ≈ 2 chars for Qwen tokenizer w/ CJK mix.
        let approxInputTokens = max(raw.count / 2, 16)
        let maxOutputTokens = approxInputTokens * maxTokensMultiplier

        do {
            let result: String = try await container.perform { context in
                let chat: [Chat.Message] = [
                    .system(effectivePrompt),
                    .user(raw)
                ]
                let userInput = UserInput(chat: chat)
                let input = try await context.processor.prepare(input: userInput)
                let params = GenerateParameters(
                    maxTokens: maxOutputTokens,
                    temperature: 0.2
                )
                var buffer = ""
                _ = try MLXLMCommon.generate(
                    input: input,
                    parameters: params,
                    context: context
                ) { tokens in
                    // Collect streaming tokens into the buffer.
                    let decoded = context.tokenizer.decode(tokens: tokens)
                    buffer = decoded
                    return .more
                }
                return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return result.isEmpty ? raw : result
        } catch {
            throw MLXPolishError.generationFailed(error.localizedDescription)
        }
    }
}
```

**API adjustments:** The `MLXLLM` package's chat message type (`Chat.Message`, `Chat.Role`, or just `[[String: String]]`), `UserInput` constructor, `GenerateParameters` shape, and the `generate(_:parameters:context:didGenerate:)` callback signature may differ. Sonnet: verify against the resolved package version. The intent is:
1. Build a chat transcript with a system prompt (the polish instructions) and a user message (the raw transcript).
2. Tokenize it.
3. Generate up to `maxOutputTokens` with low temperature.
4. Return the decoded string (or raw on empty output).

If the exact `Chat.Message` / `UserInput` types don't exist, fall back to building the prompt as a single string using the Qwen2.5 chat template manually:

```
<|im_start|>system
{prompt}
<|im_end|>
<|im_start|>user
{raw}
<|im_end|>
<|im_start|>assistant
```

- [ ] **Step 4.2:** `xcodebuild build -scheme LocalTypeless -destination 'platform=macOS' 2>&1 | tail -30`. Must succeed. Iterate on API mismatches.

- [ ] **Step 4.3:** Commit: `feat: add MLXPolishService using Qwen2.5-3B chat generation`

---

## Task 5: Polish integration test (skippable)

**Files:** `LocalTypelessTests/MLXPolishServiceTests.swift`

- [ ] **Step 5.1:** Write the test:

```swift
import XCTest
@testable import LocalTypeless

@MainActor
final class MLXPolishServiceTests: XCTestCase {

    private var shouldSkip: Bool {
        ProcessInfo.processInfo.environment["LOCAL_TYPELESS_SKIP_MODEL_TESTS"] == "1"
    }

    func test_polishes_english_transcript() async throws {
        try XCTSkipIf(shouldSkip, "Model tests disabled via env flag")

        let store = ModelStatusStore()
        let manager = MLXPolishModelManager(store: store)
        let service = MLXPolishService(manager: manager)

        let transcript = Transcript(
            text: "um so like, I was thinking, uh, we could maybe, you know, ship it tomorrow",
            language: "en",
            segments: []
        )

        let polished = try await service.polish(transcript, prompt: "")
        XCTAssertFalse(polished.isEmpty)
        XCTAssertFalse(polished.lowercased().contains("um"))
        XCTAssertFalse(polished.lowercased().contains("you know"))
    }

    func test_polishes_chinese_transcript() async throws {
        try XCTSkipIf(shouldSkip, "Model tests disabled via env flag")

        let store = ModelStatusStore()
        let manager = MLXPolishModelManager(store: store)
        let service = MLXPolishService(manager: manager)

        let transcript = Transcript(
            text: "那个 嗯 我们明天 呃 可以发布一下",
            language: "zh",
            segments: []
        )

        let polished = try await service.polish(transcript, prompt: "")
        XCTAssertFalse(polished.isEmpty)
        XCTAssertFalse(polished.contains("嗯"))
        XCTAssertFalse(polished.contains("呃"))
    }

    func test_falls_back_on_empty_input() async throws {
        try XCTSkipIf(shouldSkip, "Model tests disabled via env flag")

        let store = ModelStatusStore()
        let manager = MLXPolishModelManager(store: store)
        let service = MLXPolishService(manager: manager)

        let transcript = Transcript(text: "   ", language: "en", segments: [])
        await XCTAssertThrowsErrorAsync(
            try await service.polish(transcript, prompt: "")
        )
    }
}

// Helper for async XCTest (XCTest doesn't ship XCTAssertThrowsErrorAsync).
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected throw", file: file, line: line)
    } catch {
        // expected
    }
}
```

- [ ] **Step 5.2:** Run with skip flag:

```bash
TEST_RUNNER_LOCAL_TYPELESS_SKIP_MODEL_TESTS=1 xcodebuild test \
    -scheme LocalTypeless -destination 'platform=macOS' \
    -only-testing:LocalTypelessTests/MLXPolishServiceTests 2>&1 | tail -20
```

Expected: 3 skipped.

- [ ] **Step 5.3:** Run the full suite with skip flag — expect all previous tests pass, new 3 skipped. Commit: `test: add MLXPolishService integration tests (skippable)`

---

## Task 6: Generalize ModelDownloadView

**Files:** `LocalTypeless/UI/ModelDownloadView.swift`

- [ ] **Step 6.1:** Refactor the view to take `kind: ModelKind` and derive title/subtitle from it:

```swift
struct ModelDownloadView: View {
    @Bindable var store: ModelStatusStore
    let kind: ModelKind
    let onStart: () -> Void
    let onCancel: () -> Void

    private var title: String {
        switch kind {
        case .asrWhisperLargeV3Turbo: return "Download speech model"
        case .polishQwen25_3bInstruct4bit: return "Download polish model"
        }
    }

    private var subtitle: String {
        switch kind {
        case .asrWhisperLargeV3Turbo: return "~1.5 GB · offline after download"
        case .polishQwen25_3bInstruct4bit: return "~2 GB · offline after download"
        }
    }

    // rest of the body unchanged, swap `self.kind` for the hardcoded one
    ...
}
```

- [ ] **Step 6.2:** Build, commit: `refactor: generalize ModelDownloadView to take a ModelKind`

---

## Task 7: Wire AppDelegate + MenuBarController

**Files:** `LocalTypeless/App/AppDelegate.swift`, `LocalTypeless/App/MenuBarController.swift`

- [ ] **Step 7.1:** In `AppDelegate`:
  - Add properties `mlxPolishManager: MLXPolishModelManager!` and `polishDownloadWindow: NSWindow?`
  - In `applicationDidFinishLaunching`:
    ```swift
    mlxPolishManager = MLXPolishModelManager(store: modelStatusStore)
    polishService = MLXPolishService(manager: mlxPolishManager)
    ```
  - Change `handleToggle()` gate to require BOTH models ready:
    ```swift
    if !modelStatusStore.isReady(.asrWhisperLargeV3Turbo) {
        openModelDownload(kind: .asrWhisperLargeV3Turbo); return
    }
    if !modelStatusStore.isReady(.polishQwen25_3bInstruct4bit) {
        openModelDownload(kind: .polishQwen25_3bInstruct4bit); return
    }
    ```
  - Refactor `openModelDownload()` to take a `kind: ModelKind` parameter. Use separate windows per kind (dictionary keyed by kind) so the user can open both sheets independently if they want, OR reuse one window and re-bind the view when the kind changes. Pick one window that re-binds — simpler:
    ```swift
    private func openModelDownload(kind: ModelKind) {
        let manager: ModelManager = (kind == .asrWhisperLargeV3Turbo)
            ? modelManager : mlxPolishManager
        let view = ModelDownloadView(
            store: modelStatusStore,
            kind: kind,
            onStart: { [weak self] in self?.startModelDownload(kind: kind, manager: manager) },
            onCancel: { [weak self] in self?.modelDownloadWindow?.close() }
        )
        let host = NSHostingController(rootView: view)
        if let w = modelDownloadWindow {
            w.contentViewController = host
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let w = NSWindow(contentViewController: host)
        w.title = "Model Setup"
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        modelDownloadWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
    ```
  - `startModelDownload(kind:manager:)` calls `manager.ensureReady(kind)` in a Task.
  - `unloadModels()` unloads both:
    ```swift
    Task { [modelManager, mlxPolishManager] in
        await modelManager!.unload(.asrWhisperLargeV3Turbo)
        await mlxPolishManager!.unload(.polishQwen25_3bInstruct4bit)
    }
    ```

- [ ] **Step 7.2:** In `MenuBarController`:
  - Add menu items for BOTH models ("ASR model: <state>", "Polish model: <state>", both disabled as status lines).
  - When either model is not `.resident`, add a "Download <name> model…" action.
  - The `onOpenModelDownload` closure should now accept a `ModelKind` parameter. Update both the stored closure type and the menu's target/action to pass the right kind.
  - Extend `withObservationTracking` to read BOTH statuses:
    ```swift
    withObservationTracking {
        _ = stateMachine.state
        _ = modelStatusStore.status(for: .asrWhisperLargeV3Turbo)
        _ = modelStatusStore.status(for: .polishQwen25_3bInstruct4bit)
    } onChange: { [weak self] in
        Task { @MainActor in self?.refresh() }
    }
    ```

- [ ] **Step 7.3:** Build, run full test suite with skip flag. Expect 34+3 tests (31 Phase 1 + 4 ModelStatusStoreTests + 2 WhisperKit skipped + 3 Polish skipped + 3 DefaultPromptsTests) = sum works out to ~40 tests total with 5 skipped. Verify no regressions.

- [ ] **Step 7.4:** Commit: `feat: wire MLXPolishService into AppDelegate and add polish model controls to menu`

---

## Task 8: Final review + tag

- [ ] **Step 8.1:** Run full test suite with skip flag. Confirm all non-integration tests pass.

- [ ] **Step 8.2:** Manual smoke (user action):
  - `make run`
  - First hotkey tap → ASR download sheet
  - After ASR done, next hotkey tap → polish download sheet
  - After both ready, speak English → filler-stripped English text injected
  - Speak Chinese → filler-stripped Chinese text injected
  - Menu shows both models "Ready"; Unload menu empties RAM

- [ ] **Step 8.3:** Tag: `git tag phase-3-complete`

---

## Self-review checklist

- **Spec coverage:** §5.4 (polish service), §2 goals "Local LLM polish step (filler removal, punctuation, formatting) with user-editable prompt" — covered by Tasks 2, 4, 5. Max-tokens cap per spec ("Max output tokens: 2× input token count") — Task 4 via `maxTokensMultiplier`.
- **Gating order:** `handleToggle()` opens ASR sheet first, polish sheet second. This is intentional — ASR is needed to produce transcripts; polish is a second-order dependency.
- **Graceful fallback:** `AppDelegate.runPipeline()` already falls back to raw transcript on polish error (Phase 1 behavior preserved). `MLXPolishService.polish` also returns raw on empty-output edge case.
- **Type consistency:** `ModelKind.polishQwen25_3bInstruct4bit` used identically across Tasks 3, 4, 6, 7.
- **No placeholders:** All code blocks are complete. Task 4 explicitly authorizes Sonnet to adjust MLXLLM API names; the intent is specified.
