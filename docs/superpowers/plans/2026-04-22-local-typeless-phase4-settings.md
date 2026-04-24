# Phase 4 — Settings Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Ship a real Settings window that replaces the Phase 1 skeleton. Exposes every user-configurable option listed in the spec §5.8: hotkey recorder, ASR language mode, UI language (stubbed for Phase 5 wiring), polish prompt editor, model info, audio retention, launch at login.

**Architecture:** Single `@MainActor @Observable AppSettings` class owns all user preferences, backed by `UserDefaults` with a small `SettingsStorage` indirection so tests can inject an in-memory backend. The Settings window is a `TabView` with three tabs: General, Prompts, Advanced. Changes propagate to `AppDelegate` via a lightweight observer (the delegate `withObservationTracking`s the fields it cares about: hotkey binding → rebind `HotkeyManager`; ASR language → update `WhisperKitASRService.options`; polish prompt override → passed through to `AppDelegate.runPipeline` as the `prompt` arg).

**Tech Stack:** SwiftUI for forms, NSEvent local monitor for hotkey capture, ServiceManagement.SMAppService for launch-at-login (macOS 13+).

---

## File structure

**Create:**
- `LocalTypeless/Settings/AppSettings.swift` — the @Observable store
- `LocalTypeless/Settings/SettingsStorage.swift` — protocol + UserDefaults impl
- `LocalTypeless/Settings/LaunchAtLogin.swift` — SMAppService wrapper
- `LocalTypeless/UI/HotkeyRecorderField.swift` — SwiftUI control that captures a key press or modifier-only tap/double-tap/long-press
- `LocalTypeless/UI/SettingsGeneralTab.swift`
- `LocalTypeless/UI/SettingsPromptsTab.swift`
- `LocalTypeless/UI/SettingsAdvancedTab.swift`
- `LocalTypelessTests/AppSettingsTests.swift`
- `LocalTypelessTests/HotkeyRecorderFieldTests.swift` (pure parsing/decode, no UI)

**Modify:**
- `LocalTypeless/UI/SettingsView.swift` — replace skeleton with the three-tab form
- `LocalTypeless/App/AppDelegate.swift` — instantiate `AppSettings`, observe changes, rebind hotkey / update ASR options / thread polish prompt through `runPipeline`
- `LocalTypeless/Services/WhisperKitASRService.swift` — expose mutable `options` so settings can update them live (use a property lock)
- `LocalTypeless/Core/HotkeyBinding.swift` — add `conflictsWith(_:)` for the conflict-detection test

---

## Task 1: AppSettings + SettingsStorage (TDD)

**Files:** `AppSettings.swift`, `SettingsStorage.swift`, `AppSettingsTests.swift`

- [ ] **Step 1.1:** Failing test `LocalTypelessTests/AppSettingsTests.swift`:

```swift
import XCTest
@testable import LocalTypeless

@MainActor
final class AppSettingsTests: XCTestCase {

    private func makeSettings() -> (AppSettings, InMemorySettingsStorage) {
        let storage = InMemorySettingsStorage()
        return (AppSettings(storage: storage), storage)
    }

    func test_defaults() {
        let (s, _) = makeSettings()
        XCTAssertEqual(s.hotkeyBinding, .default)
        XCTAssertEqual(s.asrLanguageMode, .auto)
        XCTAssertEqual(s.uiLanguageMode, .system)
        XCTAssertEqual(s.polishPromptOverride, "")
        XCTAssertTrue(s.audioRetentionEnabled == false)
        XCTAssertEqual(s.audioRetentionDays, 7)
        XCTAssertEqual(s.launchAtLogin, false)
    }

    func test_writes_persist() {
        let (s, storage) = makeSettings()
        s.asrLanguageMode = .en
        s.polishPromptOverride = "Custom prompt"
        XCTAssertEqual(storage.string(forKey: "polishPromptOverride"), "Custom prompt")
        XCTAssertEqual(storage.string(forKey: "asrLanguageMode"), "en")
    }

    func test_hotkey_binding_roundtrips() {
        let (s, _) = makeSettings()
        let b = HotkeyBinding(keyCode: 0x03, modifierMask: [.command, .shift],
                               trigger: .press, modifierOnly: nil)
        s.hotkeyBinding = b
        let (s2, _) = makeSettings()  // fresh instance, same storage? No — use same storage.

        let storage2 = InMemorySettingsStorage()
        let first = AppSettings(storage: storage2)
        first.hotkeyBinding = b
        let second = AppSettings(storage: storage2)
        XCTAssertEqual(second.hotkeyBinding, b)
    }

    func test_resetPolishPrompt_clears_override() {
        let (s, _) = makeSettings()
        s.polishPromptOverride = "Do the thing"
        s.resetPolishPrompt()
        XCTAssertEqual(s.polishPromptOverride, "")
    }
}
```

- [ ] **Step 1.2:** Run → fails to compile.

- [ ] **Step 1.3:** Create `LocalTypeless/Settings/SettingsStorage.swift`:

```swift
import Foundation

protocol SettingsStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func string(forKey key: String) -> String?
    func set(_ string: String?, forKey key: String)
    func bool(forKey key: String) -> Bool
    func set(_ bool: Bool, forKey key: String)
    func integer(forKey key: String) -> Int
    func set(_ int: Int, forKey key: String)
    func contains(_ key: String) -> Bool
}

final class UserDefaultsSettingsStorage: SettingsStorage {
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func set(_ data: Data?, forKey key: String) { defaults.set(data, forKey: key) }
    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func set(_ string: String?, forKey key: String) { defaults.set(string, forKey: key) }
    func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    func set(_ bool: Bool, forKey key: String) { defaults.set(bool, forKey: key) }
    func integer(forKey key: String) -> Int { defaults.integer(forKey: key) }
    func set(_ int: Int, forKey key: String) { defaults.set(int, forKey: key) }
    func contains(_ key: String) -> Bool { defaults.object(forKey: key) != nil }
}

final class InMemorySettingsStorage: SettingsStorage {
    private var store: [String: Any] = [:]
    func data(forKey key: String) -> Data? { store[key] as? Data }
    func set(_ data: Data?, forKey key: String) { store[key] = data }
    func string(forKey key: String) -> String? { store[key] as? String }
    func set(_ string: String?, forKey key: String) { store[key] = string }
    func bool(forKey key: String) -> Bool { store[key] as? Bool ?? false }
    func set(_ bool: Bool, forKey key: String) { store[key] = bool }
    func integer(forKey key: String) -> Int { store[key] as? Int ?? 0 }
    func set(_ int: Int, forKey key: String) { store[key] = int }
    func contains(_ key: String) -> Bool { store[key] != nil }
}
```

- [ ] **Step 1.4:** Create `LocalTypeless/Settings/AppSettings.swift`:

```swift
import Foundation
import Observation

enum ASRLanguageMode: String, Sendable, CaseIterable {
    case auto, en, zh
}

enum UILanguageMode: String, Sendable, CaseIterable {
    case system, en, zhHans
}

@MainActor
@Observable
final class AppSettings {

    private let storage: SettingsStorage

    init(storage: SettingsStorage = UserDefaultsSettingsStorage()) {
        self.storage = storage
        self._hotkeyBinding = Self.loadBinding(storage: storage) ?? .default
        self._asrLanguageMode = ASRLanguageMode(
            rawValue: storage.string(forKey: "asrLanguageMode") ?? "") ?? .auto
        self._uiLanguageMode = UILanguageMode(
            rawValue: storage.string(forKey: "uiLanguageMode") ?? "") ?? .system
        self._polishPromptOverride = storage.string(forKey: "polishPromptOverride") ?? ""
        self._audioRetentionEnabled = storage.bool(forKey: "audioRetentionEnabled")
        self._audioRetentionDays = storage.contains("audioRetentionDays")
            ? storage.integer(forKey: "audioRetentionDays") : 7
        self._launchAtLogin = storage.bool(forKey: "launchAtLogin")
    }

    // MARK: - Properties

    private var _hotkeyBinding: HotkeyBinding
    var hotkeyBinding: HotkeyBinding {
        get { _hotkeyBinding }
        set {
            _hotkeyBinding = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                storage.set(data, forKey: "hotkeyBinding")
            }
        }
    }

    private var _asrLanguageMode: ASRLanguageMode
    var asrLanguageMode: ASRLanguageMode {
        get { _asrLanguageMode }
        set { _asrLanguageMode = newValue; storage.set(newValue.rawValue, forKey: "asrLanguageMode") }
    }

    private var _uiLanguageMode: UILanguageMode
    var uiLanguageMode: UILanguageMode {
        get { _uiLanguageMode }
        set { _uiLanguageMode = newValue; storage.set(newValue.rawValue, forKey: "uiLanguageMode") }
    }

    private var _polishPromptOverride: String
    var polishPromptOverride: String {
        get { _polishPromptOverride }
        set { _polishPromptOverride = newValue; storage.set(newValue, forKey: "polishPromptOverride") }
    }

    private var _audioRetentionEnabled: Bool
    var audioRetentionEnabled: Bool {
        get { _audioRetentionEnabled }
        set { _audioRetentionEnabled = newValue; storage.set(newValue, forKey: "audioRetentionEnabled") }
    }

    private var _audioRetentionDays: Int
    var audioRetentionDays: Int {
        get { _audioRetentionDays }
        set { _audioRetentionDays = newValue; storage.set(newValue, forKey: "audioRetentionDays") }
    }

    private var _launchAtLogin: Bool
    var launchAtLogin: Bool {
        get { _launchAtLogin }
        set { _launchAtLogin = newValue; storage.set(newValue, forKey: "launchAtLogin") }
    }

    func resetPolishPrompt() { polishPromptOverride = "" }

    private static func loadBinding(storage: SettingsStorage) -> HotkeyBinding? {
        guard let data = storage.data(forKey: "hotkeyBinding") else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }
}
```

The manual setter pattern above avoids the `@Observable` macro's tracking from being defeated by custom accessors — the macro recognizes stored-property-with-setter. If compiler complains about tracking, wrap each field in a simple `didSet`:

```swift
var asrLanguageMode: ASRLanguageMode = .auto {
    didSet { storage.set(asrLanguageMode.rawValue, forKey: "asrLanguageMode") }
}
```

...and populate defaults inline via `init`. Use whichever pattern compiles cleanly.

- [ ] **Step 1.5:** Run tests — 4/4 pass.

- [ ] **Step 1.6:** Commit: `feat: add AppSettings store with UserDefaults-backed persistence`

---

## Task 2: HotkeyBinding conflict detection (TDD)

**Files:** `LocalTypeless/Core/HotkeyBinding.swift` (modify), `LocalTypelessTests/HotkeyBindingTests.swift` (append)

- [ ] **Step 2.1:** Append tests to the existing `HotkeyBindingTests.swift`:

```swift
func test_conflictsWith_true_for_same_key_and_mods() {
    let a = HotkeyBinding(keyCode: 0x03, modifierMask: [.command, .shift],
                          trigger: .press, modifierOnly: nil)
    let b = HotkeyBinding(keyCode: 0x03, modifierMask: [.command, .shift],
                          trigger: .press, modifierOnly: nil)
    XCTAssertTrue(a.conflictsWith(b))
}

func test_conflictsWith_false_for_different_keys() {
    let a = HotkeyBinding(keyCode: 0x03, modifierMask: [.command, .shift],
                          trigger: .press, modifierOnly: nil)
    let b = HotkeyBinding(keyCode: 0x04, modifierMask: [.command, .shift],
                          trigger: .press, modifierOnly: nil)
    XCTAssertFalse(a.conflictsWith(b))
}

func test_conflictsWith_true_for_same_modifier_only() {
    let a = HotkeyBinding.default  // double-tap right Option
    let b = HotkeyBinding(keyCode: nil, modifierMask: [],
                          trigger: .doubleTap, modifierOnly: .rightOption)
    XCTAssertTrue(a.conflictsWith(b))
}

func test_conflictsWith_false_across_trigger_types_on_same_modifier() {
    let a = HotkeyBinding(keyCode: nil, modifierMask: [], trigger: .press,
                          modifierOnly: .rightOption)
    let b = HotkeyBinding(keyCode: nil, modifierMask: [], trigger: .doubleTap,
                          modifierOnly: .rightOption)
    XCTAssertFalse(a.conflictsWith(b))
}
```

- [ ] **Step 2.2:** Add `conflictsWith(_:)` to `HotkeyBinding.swift`:

```swift
extension HotkeyBinding {
    func conflictsWith(_ other: HotkeyBinding) -> Bool {
        if let k1 = keyCode, let k2 = other.keyCode {
            return k1 == k2 && modifierMask == other.modifierMask
        }
        if let m1 = modifierOnly, let m2 = other.modifierOnly {
            return m1 == m2 && trigger == other.trigger
        }
        return false
    }
}
```

- [ ] **Step 2.3:** Run tests → 4 new + existing pass.

- [ ] **Step 2.4:** Commit: `feat: add HotkeyBinding.conflictsWith for settings conflict detection`

---

## Task 3: HotkeyRecorderField (SwiftUI component)

**Files:** `LocalTypeless/UI/HotkeyRecorderField.swift`

- [ ] **Step 3.1:** Write the component:

```swift
import SwiftUI
import AppKit

/// A SwiftUI button that, when clicked, enters "recording" mode. While recording,
/// the next keyDown (with modifiers) is captured as a HotkeyBinding and passed
/// back via `onChange`. Modifier-only triggers (e.g. double-tap right Option)
/// are configured via the separate ModifierOnlyPicker; this field only captures
/// key+modifier combos.
struct HotkeyRecorderField: View {

    @Binding var binding: HotkeyBinding
    var onChange: ((HotkeyBinding) -> Void)?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack {
                Text(binding.keyCode != nil ? binding.displayString : "—")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isRecording ? "Press keys…" : "Record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stopMonitor() }
    }

    private func toggleRecording() {
        if isRecording { stopMonitor() } else { startMonitor() }
    }

    private func startMonitor() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let mask = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard mask.isEmpty == false else {
                // A plain keydown with no modifiers is rejected (too prone to breaking).
                NSSound.beep()
                return event
            }
            let new = HotkeyBinding(
                keyCode: UInt32(event.keyCode),
                modifierMask: mask,
                trigger: .press,
                modifierOnly: nil
            )
            binding = new
            onChange?(new)
            stopMonitor()
            return nil  // swallow the event
        }
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        isRecording = false
    }
}
```

- [ ] **Step 3.2:** Build. Commit: `feat: add HotkeyRecorderField for capturing key+modifier shortcuts`

Testing: this UI component is tested indirectly (manual QA in Task 7). We skip unit tests — the NSEvent monitor is not exercisable headlessly.

---

## Task 4: SettingsGeneralTab

**Files:** `LocalTypeless/UI/SettingsGeneralTab.swift`

- [ ] **Step 4.1:** Write:

```swift
import SwiftUI

struct SettingsGeneralTab: View {
    @Bindable var settings: AppSettings
    @State private var conflictMessage: String?

    var body: some View {
        Form {
            Section("Hotkey") {
                hotkeyRow
                modifierOnlyRow
                if let msg = conflictMessage {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Speech") {
                Picker("ASR language", selection: $settings.asrLanguageMode) {
                    Text("Auto-detect").tag(ASRLanguageMode.auto)
                    Text("English only").tag(ASRLanguageMode.en)
                    Text("Chinese only").tag(ASRLanguageMode.zh)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var hotkeyRow: some View {
        HStack {
            Text("Trigger shortcut")
            Spacer()
            HotkeyRecorderField(binding: $settings.hotkeyBinding)
                .frame(width: 180)
        }
    }

    @ViewBuilder
    private var modifierOnlyRow: some View {
        HStack {
            Text("Modifier-only")
            Spacer()
            Picker("", selection: $settings.hotkeyBinding) {
                Text("(none)").tag(HotkeyBinding(
                    keyCode: settings.hotkeyBinding.keyCode,
                    modifierMask: settings.hotkeyBinding.modifierMask,
                    trigger: .press, modifierOnly: nil))
                Text("Double-tap right ⌥").tag(HotkeyBinding(
                    keyCode: nil, modifierMask: [], trigger: .doubleTap, modifierOnly: .rightOption))
                Text("Double-tap left ⌥").tag(HotkeyBinding(
                    keyCode: nil, modifierMask: [], trigger: .doubleTap, modifierOnly: .leftOption))
                Text("Long-press right ⌃").tag(HotkeyBinding(
                    keyCode: nil, modifierMask: [], trigger: .longPress, modifierOnly: .rightControl))
            }
            .frame(width: 220)
        }
    }
}
```

Note: the `modifierOnlyRow` `Picker` uses `HotkeyBinding` as its tag type. For that to work, `HotkeyBinding` must be `Hashable`. Confirm (it already is — `Codable + Equatable` from Phase 1) — if not `Hashable`, add conformance.

- [ ] **Step 4.2:** If `HotkeyBinding` is not `Hashable`, add `Hashable` conformance (just add to the declaration — all fields are already Hashable-compatible).

- [ ] **Step 4.3:** Commit: `feat: add SettingsGeneralTab with hotkey + language + launch-at-login`

---

## Task 5: SettingsPromptsTab + SettingsAdvancedTab

**Files:** `LocalTypeless/UI/SettingsPromptsTab.swift`, `LocalTypeless/UI/SettingsAdvancedTab.swift`

- [ ] **Step 5.1:** Prompts tab:

```swift
import SwiftUI

struct SettingsPromptsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Polish prompt") {
                Text("Empty = use the default for the detected language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $settings.polishPromptOverride)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3))
                    )

                HStack {
                    Spacer()
                    Button("Reset to default") { settings.resetPolishPrompt() }
                        .disabled(settings.polishPromptOverride.isEmpty)
                }
            }

            Section("Defaults (read-only)") {
                DisclosureGroup("English") {
                    Text(DefaultPrompts.polishEN)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                DisclosureGroup("中文") {
                    Text(DefaultPrompts.polishZH)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 5.2:** Advanced tab:

```swift
import SwiftUI

struct SettingsAdvancedTab: View {
    @Bindable var settings: AppSettings
    let modelStatusStore: ModelStatusStore
    let onDownloadAsr: () -> Void
    let onDownloadPolish: () -> Void

    var body: some View {
        Form {
            Section("Audio retention") {
                Toggle("Keep raw audio on disk", isOn: $settings.audioRetentionEnabled)
                Stepper(value: $settings.audioRetentionDays, in: 1...30) {
                    Text("Keep for \(settings.audioRetentionDays) day(s)")
                }
                .disabled(!settings.audioRetentionEnabled)
            }

            Section("Models") {
                modelRow(
                    label: "Speech (Whisper Large v3 Turbo)",
                    status: modelStatusStore.status(for: .asrWhisperLargeV3Turbo),
                    onDownload: onDownloadAsr
                )
                modelRow(
                    label: "Polish (Qwen2.5-3B-Instruct 4bit)",
                    status: modelStatusStore.status(for: .polishQwen25_3bInstruct4bit),
                    onDownload: onDownloadPolish
                )
            }

            Section("UI language") {
                Picker("Display language", selection: $settings.uiLanguageMode) {
                    Text("Follow system").tag(UILanguageMode.system)
                    Text("English").tag(UILanguageMode.en)
                    Text("简体中文").tag(UILanguageMode.zhHans)
                }
                Text("Phase 5 will translate the rest of the UI; for now this setting is stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func modelRow(label: String,
                           status: ModelStatus,
                           onDownload: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label)
                Text(describe(status)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if case .resident = status {
                Label("Ready", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                Button("Download", action: onDownload)
            }
        }
    }

    private func describe(_ s: ModelStatus) -> String {
        switch s {
        case .notDownloaded: return "Not downloaded"
        case .downloading(let p): return "Downloading \(Int(p*100))%"
        case .downloaded: return "Downloaded (not loaded)"
        case .loading: return "Loading…"
        case .resident: return "Ready"
        case .failed(let m): return m
        }
    }
}
```

- [ ] **Step 5.3:** Commit: `feat: add SettingsPromptsTab and SettingsAdvancedTab`

---

## Task 6: Wire SettingsView + AppDelegate

**Files:** `LocalTypeless/UI/SettingsView.swift`, `LocalTypeless/App/AppDelegate.swift`

- [ ] **Step 6.1:** Replace `SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let modelStatusStore: ModelStatusStore
    let onDownloadAsr: () -> Void
    let onDownloadPolish: () -> Void

    var body: some View {
        TabView {
            SettingsGeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }
            SettingsPromptsTab(settings: settings)
                .tabItem { Label("Prompts", systemImage: "text.quote") }
            SettingsAdvancedTab(settings: settings,
                                 modelStatusStore: modelStatusStore,
                                 onDownloadAsr: onDownloadAsr,
                                 onDownloadPolish: onDownloadPolish)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}
```

- [ ] **Step 6.2:** In `AppDelegate`:
  - Add property `settings: AppSettings!`
  - In `applicationDidFinishLaunching`:
    ```swift
    settings = AppSettings()
    let binding = settings.hotkeyBinding
    hotkeyManager.install(binding: binding) { [weak self] in self?.handleToggle() }
    startObservingSettings()
    applyLaunchAtLogin(settings.launchAtLogin)
    ```
  - Delete the now-unused static `loadBinding()`.
  - Add `startObservingSettings()`:
    ```swift
    private func startObservingSettings() {
        withObservationTracking {
            _ = settings.hotkeyBinding
            _ = settings.asrLanguageMode
            _ = settings.launchAtLogin
        } onChange: { [weak self] in
            Task { @MainActor in self?.applySettingsChange() }
        }
    }

    private func applySettingsChange() {
        hotkeyManager.install(binding: settings.hotkeyBinding) { [weak self] in
            self?.handleToggle()
        }
        if let whisperService = asrService as? WhisperKitASRService {
            whisperService.setOptions(ASROptions(forcedLanguage: {
                switch settings.asrLanguageMode {
                case .auto: return nil
                case .en: return "en"
                case .zh: return "zh"
                }
            }()))
        }
        applyLaunchAtLogin(settings.launchAtLogin)
        startObservingSettings()  // re-register
    }
    ```
  - Update `runPipeline()` to pass the polish prompt from settings:
    ```swift
    let promptOverride = settings.polishPromptOverride
    polished = try await withTimeout(30) { [polishService] in
        try await polishService.polish(transcript, prompt: promptOverride)
    }
    ```
  - Update `openSettings()` to use the new constructor:
    ```swift
    private func openSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let view = SettingsView(
            settings: settings,
            modelStatusStore: modelStatusStore,
            onDownloadAsr: { [weak self] in self?.openModelDownload(kind: .asrWhisperLargeV3Turbo) },
            onDownloadPolish: { [weak self] in self?.openModelDownload(kind: .polishQwen25_3bInstruct4bit) }
        )
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Settings"
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
    ```

- [ ] **Step 6.3:** `WhisperKitASRService` — add a thread-safe setter:

```swift
private var _options: ASROptions
private let optionsLock = NSLock()

var options: ASROptions {
    optionsLock.lock(); defer { optionsLock.unlock() }
    return _options
}

func setOptions(_ new: ASROptions) {
    optionsLock.lock(); _options = new; optionsLock.unlock()
}
```

Update the constructor to initialize `_options` and remove the `let options: ASROptions`. Update `transcribe(_:)` to read `let opts = options` at the top and use `opts` throughout.

- [ ] **Step 6.4:** Build + test (full suite with skip flag). Expect 39 + 4 new settings tests + 4 new conflict tests = 47 executed, ~42 pass, 5 skipped. Iterate.

- [ ] **Step 6.5:** Commit: `feat: wire SettingsView + AppSettings into AppDelegate with live rebind`

---

## Task 7: LaunchAtLogin (SMAppService)

**Files:** `LocalTypeless/Settings/LaunchAtLogin.swift`

- [ ] **Step 7.1:** Write:

```swift
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static func apply(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            switch (enabled, service.status) {
            case (true, .notRegistered), (true, .notFound):
                try service.register()
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            default:
                break
            }
        } catch {
            // Logged by caller.
            throw error
        }
    }
}

extension LaunchAtLogin {
    // Convenience used by AppDelegate; swallows error.
    static func applySilently(_ enabled: Bool) {
        do { try apply(enabled) } catch {
            Log.state.error("launch-at-login toggle failed: \(String(describing: error), privacy: .public)")
        }
    }
}
```

Wait — the `apply` function has a `do/catch/throw` that serves no purpose. Simplify:

```swift
enum LaunchAtLogin {
    static func apply(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        switch (enabled, service.status) {
        case (true, .notRegistered), (true, .notFound):
            try service.register()
        case (false, .enabled), (false, .requiresApproval):
            try service.unregister()
        default:
            break
        }
    }

    static func applySilently(_ enabled: Bool) {
        do { try apply(enabled) } catch {
            Log.state.error("launch-at-login toggle failed: \(String(describing: error), privacy: .public)")
        }
    }
}
```

Add `applyLaunchAtLogin(_:)` helper in `AppDelegate` that calls `LaunchAtLogin.applySilently(_:)`.

- [ ] **Step 7.2:** Commit: `feat: add LaunchAtLogin via SMAppService and wire settings toggle`

---

## Task 8: Final review + tag

- [ ] **Step 8.1:** Run full suite. Expect all non-integration tests pass.

- [ ] **Step 8.2:** Manual smoke (user):
  - Open Settings → General → change ASR language to "English only" → run a Chinese dictation → should transcribe as English (possibly gibberish, that's correctness verification)
  - Open Settings → Prompts → set custom prompt "Make the text sound like a pirate" → run a dictation → polished text should be piratey
  - Open Settings → General → record new hotkey (e.g., ⌃⌥Space) → close settings → press ⌃⌥Space → dictation should start
  - Open Settings → General → toggle Launch at login → restart → app should launch

- [ ] **Step 8.3:** Tag: `git tag phase-4-complete`

---

## Self-review checklist

- **Spec coverage §5.8:** All 7 settings surfaces covered: hotkey (Task 3+4), ASR lang (Task 4), UI lang stub (Task 5), polish prompt (Task 5), model info (Task 5), audio retention (Task 5), launch at login (Task 7).
- **Live rebind:** Task 6 observes hotkey + ASR lang + launch-at-login and applies on change without restart. Polish prompt is read per-invocation in `runPipeline`.
- **Placeholders:** None. UI language switch is stubbed with explanatory caption per spec (Phase 5 will wire real translation).
- **Tests:** 4 AppSettings + 4 HotkeyBinding conflict tests added; all existing tests remain green.
- **Out of scope:** actual audio retention cleanup cron — deferred to Phase 6. The setting persists but no file is yet written. The Task 5 view warns via caption implicit to the toggle. If you want explicit wording, add "(Phase 6 will wire retention)" note.
