# Phase 6: Onboarding, Permissions, and Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Close out v1 by shipping (a) a guided first-launch onboarding that walks users through the three required permissions, (b) audio retention on-disk storage with rolling cleanup, and (c) a cleanup refactor to split the overloaded `ModelManager` protocol.

**Architecture:**
1. `FirstRunState` persists in UserDefaults whether onboarding completed.
2. `PermissionChecker` (new, `@MainActor`) exposes live status for Microphone, Accessibility, and Input Monitoring via Apple APIs.
3. `OnboardingView` (new SwiftUI window) walks through permissions with status badges and deep-links into System Settings. Shown iff `FirstRunState.completed == false`.
4. `AudioStore` (new) writes WAV files to `~/Library/Application Support/local-typeless/audio/<uuid>.wav` iff `settings.audioRetentionEnabled`, and prunes files older than `settings.audioRetentionDays` on launch + after each save.
5. `ModelManager` protocol splits into `ASRModelManaging` and `PolishModelManaging` — no shared `WhisperKit?` getter that only makes sense for the ASR variant.

**Tech stack:** Swift 5.9+, AVFoundation (`AVCaptureDevice` permission check), ApplicationServices (`AXIsProcessTrusted`), IOKit (`IOHIDCheckAccess`), AppKit (`NSWorkspace.open`), AVFoundation `AVAudioFile` for WAV write, XCTest.

---

## Task 1: Protocol split (ASRModelManaging + PolishModelManaging)

**Files:**
- Modify: `LocalTypeless/Services/Models/ModelManager.swift` (rename or split)
- Modify: `LocalTypeless/Services/Models/WhisperKitModelManager.swift`
- Modify: `LocalTypeless/Services/Models/MLXPolishModelManager.swift`
- Modify: `LocalTypeless/Services/WhisperKitASRService.swift`
- Modify: `LocalTypeless/Services/MLXPolishService.swift`
- Modify: `LocalTypeless/App/AppDelegate.swift`

**Goal:** Replace the single `ModelManager` protocol (which had an awkward `whisperKit` getter polluting the polish manager) with two focused protocols. Eliminate the `WhisperKit?` smell.

- [ ] **Step 1.1:** Read current `ModelManager.swift` to understand the existing protocol surface.

- [ ] **Step 1.2:** Rewrite the protocol as two:

```swift
// LocalTypeless/Services/Models/ModelManager.swift
import Foundation

protocol ModelLifecycle: Actor {
    func ensureReady(_ kind: ModelKind) async throws
    func unload(_ kind: ModelKind) async
}

protocol ASRModelManaging: ModelLifecycle {
    /// nil until ensureReady succeeds.
    var whisperKit: WhisperKit? { get async }
}

protocol PolishModelManaging: ModelLifecycle {
    /// Resolves a generation given a prompt + user text. Implementation decides how to talk to its model container.
    func generate(system: String, user: String) async throws -> String
}
```

(If `WhisperKit` type must be imported, keep the ASR protocol in a file that imports WhisperKit; alternatively define `generate` on polish to hide MLX types behind the protocol.)

- [ ] **Step 1.3:** Update `WhisperKitModelManager` to conform to `ASRModelManaging` (was `ModelManager`). Same implementation otherwise.

- [ ] **Step 1.4:** Update `MLXPolishModelManager` to conform to `PolishModelManaging`. Move the MLX generation call out of `MLXPolishService` into the manager's `generate(system:user:)` — the manager already has the ModelContainer, so this is a natural fit. Then `MLXPolishService` just calls `manager.generate(...)` and doesn't need to touch MLXLMCommon types directly. (If the current structure is simpler with MLXPolishService holding the logic, leave the service alone and just have `PolishModelManaging` expose `modelContainer: ModelContainer` or similar. Pick whichever is cleaner.)

- [ ] **Step 1.5:** Update `WhisperKitASRService` and `MLXPolishService` to take the new specific protocol types.

- [ ] **Step 1.6:** Update `AppDelegate` property declarations and initializations.

- [ ] **Step 1.7:** Build + test:

```
xcodegen generate
xcodebuild build -scheme LocalTypeless -destination 'platform=macOS' -quiet
make test
```

Expect: 48 total, 43 pass, 5 skipped (unchanged).

- [ ] **Step 1.8:** Commit: `refactor: split ModelManager into ASRModelManaging + PolishModelManaging`

---

## Task 2: PermissionChecker

**Files:**
- Create: `LocalTypeless/Permissions/PermissionChecker.swift`
- Create: `LocalTypelessTests/PermissionCheckerTests.swift` (minimal — most logic is system API wrapping)

**Goal:** Single @MainActor type that exposes live permission status for the three required APIs + deep-link helpers.

- [ ] **Step 2.1:** Write the test skeleton:

```swift
import XCTest
@testable import LocalTypeless

@MainActor
final class PermissionCheckerTests: XCTestCase {

    func test_status_is_one_of_allowed_cases() {
        let checker = PermissionChecker()
        // Status returns a real system value — we just check it's a valid enum case.
        let mic = checker.microphoneStatus
        XCTAssertTrue([.granted, .denied, .notDetermined].contains(mic))

        let ax = checker.accessibilityStatus
        XCTAssertTrue([.granted, .denied].contains(ax))

        let hid = checker.inputMonitoringStatus
        XCTAssertTrue([.granted, .denied, .notDetermined].contains(hid))
    }

    func test_deepLink_urls_are_valid() {
        XCTAssertNotNil(PermissionChecker.systemSettingsURL(for: .microphone))
        XCTAssertNotNil(PermissionChecker.systemSettingsURL(for: .accessibility))
        XCTAssertNotNil(PermissionChecker.systemSettingsURL(for: .inputMonitoring))
    }
}
```

- [ ] **Step 2.2:** Run test — fails (type not defined).

- [ ] **Step 2.3:** Implement:

```swift
import AVFoundation
import AppKit
import ApplicationServices
import IOKit.hid

@MainActor
final class PermissionChecker {

    enum Status: Equatable {
        case granted
        case denied
        case notDetermined
    }

    enum Kind: String {
        case microphone
        case accessibility
        case inputMonitoring
    }

    var microphoneStatus: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:        return .granted
        case .denied, .restricted: return .denied
        case .notDetermined:     return .notDetermined
        @unknown default:        return .notDetermined
        }
    }

    var accessibilityStatus: Status {
        AXIsProcessTrusted() ? .granted : .denied
    }

    var inputMonitoringStatus: Status {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch access {
        case kIOHIDAccessTypeGranted:       return .granted
        case kIOHIDAccessTypeDenied:        return .denied
        case kIOHIDAccessTypeUnknown:       return .notDetermined
        default:                             return .notDetermined
        }
    }

    /// Triggers the permission prompt for microphone. Other two prompt on first use.
    func requestMicrophoneIfNeeded() async -> Status {
        if microphoneStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        return microphoneStatus
    }

    static func systemSettingsURL(for kind: Kind) -> URL? {
        switch kind {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }

    static func openSystemSettings(for kind: Kind) {
        guard let url = systemSettingsURL(for: kind) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2.4:** Run tests → 2 new pass.

- [ ] **Step 2.5:** Commit: `feat: add PermissionChecker with live status and deep-link helpers`

---

## Task 3: FirstRunState

**Files:**
- Create: `LocalTypeless/Settings/FirstRunState.swift`
- Create: `LocalTypelessTests/FirstRunStateTests.swift` (2 tests)

**Goal:** Persist onboarding completion in UserDefaults so returning users aren't re-prompted.

- [ ] **Step 3.1:** Write tests:

```swift
import XCTest
@testable import LocalTypeless

@MainActor
final class FirstRunStateTests: XCTestCase {

    func test_default_not_completed() {
        let defaults = UserDefaults(suiteName: "FirstRunTests")!
        defaults.removePersistentDomain(forName: "FirstRunTests")
        let state = FirstRunState(defaults: defaults)
        XCTAssertFalse(state.onboardingCompleted)
    }

    func test_markCompleted_persists() {
        let defaults = UserDefaults(suiteName: "FirstRunTests")!
        defaults.removePersistentDomain(forName: "FirstRunTests")
        let state = FirstRunState(defaults: defaults)
        state.markOnboardingCompleted()
        XCTAssertTrue(state.onboardingCompleted)

        // New instance, same defaults
        let state2 = FirstRunState(defaults: defaults)
        XCTAssertTrue(state2.onboardingCompleted)
    }
}
```

- [ ] **Step 3.2:** Fail → implement:

```swift
import Foundation

@MainActor
final class FirstRunState {

    private let defaults: UserDefaults
    private let key = "onboardingCompleted"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var onboardingCompleted: Bool {
        defaults.bool(forKey: key)
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: key)
    }

    /// Exposed for testing + reset via Settings "Reset welcome" action.
    func reset() {
        defaults.removeObject(forKey: key)
    }
}
```

- [ ] **Step 3.3:** Run tests → pass.

- [ ] **Step 3.4:** Commit: `feat: add FirstRunState for onboarding persistence`

---

## Task 4: OnboardingView

**Files:**
- Create: `LocalTypeless/UI/OnboardingView.swift`
- Modify: `LocalTypeless/App/AppDelegate.swift` (show window on first run)

**Goal:** SwiftUI window shown on first launch. Three permission rows with live status badges + "Grant" / "Open Settings" buttons + a single "Continue" button at the bottom. Continue is enabled when mic is granted (mic blocks; accessibility + input monitoring recommended but not required per spec §7).

- [ ] **Step 4.1:** Create `OnboardingView.swift`:

```swift
import SwiftUI

struct OnboardingView: View {

    let checker: PermissionChecker
    let onContinue: () -> Void

    @State private var refreshTick: Int = 0  // bump to re-read permission status

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to local-typeless")
                .font(.title)
                .fontWeight(.semibold)
            Text("Grant three permissions so we can record, listen for the hotkey, and paste the polished text.")
                .foregroundStyle(.secondary)

            Divider()

            permissionRow(
                title: String(localized: "Microphone"),
                subtitle: String(localized: "Required to record audio"),
                systemImage: "mic.fill",
                status: checker.microphoneStatus,
                kind: .microphone,
                action: {
                    Task { @MainActor in
                        _ = await checker.requestMicrophoneIfNeeded()
                        refreshTick += 1
                    }
                }
            )
            permissionRow(
                title: String(localized: "Input Monitoring"),
                subtitle: String(localized: "Required to listen for the global hotkey"),
                systemImage: "keyboard",
                status: checker.inputMonitoringStatus,
                kind: .inputMonitoring,
                action: {
                    PermissionChecker.openSystemSettings(for: .inputMonitoring)
                }
            )
            permissionRow(
                title: String(localized: "Accessibility"),
                subtitle: String(localized: "Paste polished text into other apps (optional — clipboard fallback)"),
                systemImage: "hand.point.up.left.fill",
                status: checker.accessibilityStatus,
                kind: .accessibility,
                action: {
                    PermissionChecker.openSystemSettings(for: .accessibility)
                }
            )

            Spacer(minLength: 20)

            HStack {
                Spacer()
                Button(String(localized: "Refresh")) { refreshTick += 1 }
                Button(String(localized: "Continue"), action: onContinue)
                    .keyboardShortcut(.defaultAction)
                    .disabled(checker.microphoneStatus != .granted)
            }
        }
        .padding(32)
        .frame(width: 560, height: 480)
        .id(refreshTick) // force re-read of computed properties on each tick
    }

    @ViewBuilder
    private func permissionRow(
        title: String, subtitle: String, systemImage: String,
        status: PermissionChecker.Status, kind: PermissionChecker.Kind,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center) {
            Image(systemName: systemImage)
                .frame(width: 36, height: 36)
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(status)
            Button(status == .granted ? String(localized: "Granted") : String(localized: "Grant"),
                   action: action)
                .disabled(status == .granted)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: PermissionChecker.Status) -> some View {
        switch status {
        case .granted:
            Label(String(localized: "Granted"), systemImage: "checkmark.seal.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
        case .denied:
            Label(String(localized: "Denied"), systemImage: "xmark.seal.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
        case .notDetermined:
            Label(String(localized: "Not set"), systemImage: "questionmark.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 4.2:** Modify `AppDelegate`:

Add properties:
```swift
private var permissionChecker: PermissionChecker!
private var firstRunState: FirstRunState!
private var onboardingWindow: NSWindow?
```

In `applicationDidFinishLaunching`:
```swift
permissionChecker = PermissionChecker()
firstRunState = FirstRunState()

// ... other setup ...

if !firstRunState.onboardingCompleted {
    openOnboarding()
}
```

Add `openOnboarding()`:
```swift
private func openOnboarding() {
    if let existing = onboardingWindow {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    let view = OnboardingView(checker: permissionChecker) { [weak self] in
        self?.firstRunState.markOnboardingCompleted()
        self?.onboardingWindow?.close()
        self?.onboardingWindow = nil
    }
    let hosting = NSHostingController(rootView: view)
    let window = NSWindow(contentViewController: hosting)
    window.title = String(localized: "Welcome")
    window.styleMask = [.titled, .closable]
    window.center()
    window.isReleasedWhenClosed = false
    onboardingWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

- [ ] **Step 4.3:** Add all new localized keys to `Localizable.xcstrings`:
- "Welcome to local-typeless" / "欢迎使用 local-typeless"
- "Grant three permissions so we can record, listen for the hotkey, and paste the polished text." / "请授予以下三项权限，以便我们录音、监听快捷键并粘贴润色后的文本。"
- "Microphone" / "麦克风"
- "Required to record audio" / "录音所必需"
- "Input Monitoring" / "输入监控"
- "Required to listen for the global hotkey" / "监听全局快捷键所必需"
- "Accessibility" / "辅助功能"
- "Paste polished text into other apps (optional — clipboard fallback)" / "将润色后的文本粘贴至其他应用（可选 — 可回退至剪贴板）"
- "Refresh" / "刷新"
- "Continue" / "继续"
- "Grant" / "授予"
- "Granted" / "已授予"
- "Denied" / "已拒绝"
- "Not set" / "未设置"
- "Welcome" / "欢迎"

- [ ] **Step 4.4:** Build + manual test:
1. Reset onboarding: `defaults delete com.localtypeless.app onboardingCompleted` (or rename bundle id key — use whatever is current)
2. Relaunch app → onboarding window appears.
3. Click "Grant" next to Microphone → system prompts → grant → refresh → status flips to green.
4. Click "Continue" → window closes, menu bar app continues as normal.
5. Relaunch → onboarding NOT shown.

- [ ] **Step 4.5:** Commit: `feat: add OnboardingView with permission-walk first-run experience`

---

## Task 5: AudioStore with rolling cleanup

**Files:**
- Create: `LocalTypeless/Services/AudioStore.swift`
- Create: `LocalTypelessTests/AudioStoreTests.swift`
- Modify: `LocalTypeless/App/AppDelegate.swift` (save after recording + cleanup on launch)

**Goal:** When `settings.audioRetentionEnabled`, save WAV to Application Support; prune files older than `settings.audioRetentionDays` on launch + after each save.

- [ ] **Step 5.1:** Write tests (use tempDir, not Application Support):

```swift
import XCTest
@testable import LocalTypeless

final class AudioStoreTests: XCTestCase {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func test_save_writes_wav_file() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = AudioStore(directory: dir)
        let samples: [Float] = Array(repeating: 0.1, count: 16_000)  // 1 second
        let url = try store.save(samples: samples, sampleRate: 16_000)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertGreaterThan((attrs[.size] as? Int) ?? 0, 1000)
    }

    func test_pruneOlderThan_removes_old_files() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = AudioStore(directory: dir)
        let oldFile = dir.appendingPathComponent("old.wav")
        let newFile = dir.appendingPathComponent("new.wav")
        try Data([0]).write(to: oldFile)
        try Data([0]).write(to: newFile)

        // Backdate old file to 10 days ago
        let tenDaysAgo = Date().addingTimeInterval(-10 * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: tenDaysAgo],
            ofItemAtPath: oldFile.path
        )

        try store.pruneOlderThan(days: 7)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path))
    }
}
```

- [ ] **Step 5.2:** Fail → implement:

```swift
import AVFoundation
import Foundation

final class AudioStore: @unchecked Sendable {

    private let directory: URL
    private let fm = FileManager.default

    init(directory: URL) {
        self.directory = directory
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Defaults to `~/Library/Application Support/local-typeless/audio/`.
    static func defaultDirectory() throws -> URL {
        let app = try fm.shared.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil, create: true)
        return app.appendingPathComponent("local-typeless/audio", isDirectory: true)
    }

    @discardableResult
    func save(samples: [Float], sampleRate: Double) throws -> URL {
        let url = directory.appendingPathComponent("\(UUID().uuidString).wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                      frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            let dst = buffer.floatChannelData!.pointee
            dst.update(from: ptr.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
        return url
    }

    func pruneOlderThan(days: Int) throws {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(TimeInterval(-days) * 86_400)
        let urls = (try? fm.contentsOfDirectory(at: directory,
                                                includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in urls {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mtime, mtime < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}

// Swift: fm is a FileManager instance — convenience fix:
private extension FileManager {
    static var shared: FileManager { .default }
}
```

Fix the `fm.shared.url` syntax to `FileManager.default.url(for:...)`.

- [ ] **Step 5.3:** Wire into `AppDelegate`:

```swift
private var audioStore: AudioStore?

// in applicationDidFinishLaunching:
audioStore = (try? AudioStore(directory: AudioStore.defaultDirectory()))
// Prune on launch
if settings.audioRetentionEnabled {
    try? audioStore?.pruneOlderThan(days: settings.audioRetentionDays)
}
```

In `runPipeline`, AFTER successful transcribe + BEFORE inject:
```swift
if settings.audioRetentionEnabled, let store = audioStore {
    do {
        let samples = audioBuffer.snapshot()
        try store.save(samples: samples, sampleRate: 16_000)
        try store.pruneOlderThan(days: settings.audioRetentionDays)
    } catch {
        Log.state.error("audio save failed: \(String(describing: error), privacy: .public)")
    }
}
```

- [ ] **Step 5.4:** Run tests → expect 50 total (48 + 2 new), 45 pass, 5 skipped.

- [ ] **Step 5.5:** Commit: `feat: add AudioStore with rolling cleanup and wire into pipeline`

---

## Task 6: Open Settings from Onboarding + "Reset onboarding" action

**Files:** `LocalTypeless/UI/SettingsAdvancedTab.swift` (add reset button)

**Goal:** Let users manually re-trigger onboarding from Settings → Advanced.

- [ ] **Step 6.1:** In `SettingsAdvancedTab`, add:

```swift
Section(String(localized: "First-run experience")) {
    Button(String(localized: "Reopen welcome tour…")) {
        firstRunState.reset()
        onReopenOnboarding()
    }
}
```

Adjust signature — add `firstRunState: FirstRunState` and `onReopenOnboarding: () -> Void` to the view and plumb from `SettingsView` → `AppDelegate.openSettings()`.

- [ ] **Step 6.2:** Add keys: "First-run experience" / "首次使用体验", "Reopen welcome tour…" / "重新打开欢迎教程…"

- [ ] **Step 6.3:** Build + manual test: click reset → onboarding window reopens.

- [ ] **Step 6.4:** Commit: `feat: add reopen-welcome-tour action in Settings → Advanced`

---

## Task 7: Final review + tag

- [ ] **Step 7.1:** Run `make test` → expect 50 total, 45 pass, 5 skipped.

- [ ] **Step 7.2:** Manual smoke:
1. Delete UserDefaults key → relaunch → onboarding appears → grant mic → continue → settings shows mic granted.
2. Toggle audio retention ON in Settings → run a dictation → verify WAV file in `~/Library/Application Support/local-typeless/audio/`.
3. Wait for dial-down or fake modification time → launch → file older than `audioRetentionDays` is pruned.
4. Settings → Advanced → Reopen welcome tour → onboarding reappears.

- [ ] **Step 7.3:** Update CLAUDE.md or user docs noting v1 is feature-complete per spec.

- [ ] **Step 7.4:** Tag: `git tag phase-6-complete` and `git tag v1.0.0-rc1` (optional release candidate marker).

---

## Self-review checklist

- **Spec §7 (permissions onboarding):** ✅ Task 4 implements the guided three-permission flow with deep-linked System Settings.
- **Spec §5.6 (audio retention rolling window):** ✅ Task 5 writes WAV iff enabled, prunes older than `audioRetentionDays`.
- **Spec §8 (mic permission denied → reopen system settings):** ✅ Permission checker + settings deep-link cover it.
- **Protocol cleanup:** ✅ Task 1 splits ModelManager.
- **Placeholders:** None. Every task has concrete code.
- **Tests:** 4 new tests (2 FirstRunState + 2 AudioStore + permission status roundtrip). Coverage test from Phase 5 will catch any missed i18n keys in new UI.
- **Out of scope:** Release signing, notarization, DMG packaging — not part of the spec's v1 feature set. Note as follow-up in the commit after tagging.
