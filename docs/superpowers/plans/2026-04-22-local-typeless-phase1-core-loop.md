# local-typeless — Phase 1: Core Loop (Scaffolding + Stubbed Services)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu-bar app with the end-to-end dictation loop wired up: global hotkey → record audio → (stubbed) ASR → (stubbed) polish → inject text into the focused app, with history persistence and a skeleton Settings window. Stubs are swapped for WhisperKit and MLX Swift in later phases.

**Architecture:** Swift 5.9, SwiftUI + AppKit menu-bar app (LSUIElement). Core services (`ASRService`, `PolishService`) are behind protocols so the stubs in this phase drop out cleanly in Phase 2/3. State machine drives the menu-bar icon and ensures only one active dictation session at a time. XcodeGen generates the Xcode project from a checked-in YAML file.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, AVAudioEngine, Carbon Event Manager, CGEventTap, GRDB.swift, XcodeGen, XCTest.

**Spec reference:** [docs/superpowers/specs/2026-04-22-local-typeless-design.md](../specs/2026-04-22-local-typeless-design.md)

---

## File Structure

```
local-typeless/
├── .gitignore
├── README.md
├── project.yml                                   # XcodeGen config
├── Makefile                                      # xcodegen, build, test targets
├── LocalTypeless/
│   ├── App/
│   │   ├── LocalTypelessApp.swift                # @main
│   │   ├── AppDelegate.swift
│   │   └── MenuBarController.swift
│   ├── Core/
│   │   ├── StateMachine.swift
│   │   ├── DictationState.swift
│   │   ├── HotkeyBinding.swift
│   │   ├── HotkeyManager.swift
│   │   ├── AudioBuffer.swift
│   │   └── Recorder.swift
│   ├── Services/
│   │   ├── ASRService.swift                      # protocol + Transcript struct
│   │   ├── StubASRService.swift                  # phase-1 stub
│   │   ├── PolishService.swift                   # protocol
│   │   ├── StubPolishService.swift               # phase-1 stub
│   │   └── TextInjector.swift
│   ├── Persistence/
│   │   ├── HistoryStore.swift                    # protocol
│   │   └── SQLiteHistoryStore.swift              # GRDB impl
│   ├── UI/
│   │   ├── SettingsView.swift                    # skeleton
│   │   └── HistoryView.swift                     # skeleton
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   │   ├── AppIcon.appiconset/
│   │   │   └── MenuBarIcons/                     # idle/recording/etc
│   │   └── Info.plist
│   └── Support/
│       └── Logger.swift
├── LocalTypelessTests/
│   ├── HotkeyBindingTests.swift
│   ├── StateMachineTests.swift
│   ├── AudioBufferTests.swift
│   ├── StubASRServiceTests.swift
│   ├── StubPolishServiceTests.swift
│   ├── SQLiteHistoryStoreTests.swift
│   └── Fixtures/
│       └── sample-5s-en.wav
└── docs/
    └── superpowers/
        ├── specs/
        └── plans/
```

**Responsibilities**

- `App/` — SwiftUI app entry, AppDelegate wiring, menu-bar controller
- `Core/` — state machine, hotkey binding model, hotkey manager, audio capture
- `Services/` — swappable ASR, polish, text-injection services (protocols + concrete)
- `Persistence/` — history storage abstraction + SQLite impl
- `UI/` — Settings + History windows (skeleton in this phase, fleshed out in later phases)
- `Support/` — cross-cutting utilities (logging)
- `LocalTypelessTests/` — unit tests; integration tests live here too since the project is small

---

## Conventions Used Throughout This Plan

- **Commit style:** Conventional Commits (`feat:`, `test:`, `chore:`, `refactor:`)
- **Test runner:** `xcodebuild test -scheme LocalTypeless -destination 'platform=macOS'` (wrapped in `make test`)
- **Build:** `make build` (wraps `xcodegen generate && xcodebuild build`)
- **Swift version:** 5.9, deployment target macOS 14.0
- **After each task:** run the full test suite via `make test`. If any previously-passing test fails, stop and fix before committing.
- **Logging:** `Logger.swift` uses `os.Logger` with subsystem `com.localtypeless.app`

---

## Task 1: Repository bootstrap

**Files:**
- Create: `/Users/ming/Sites/local-typeless/.gitignore`
- Create: `/Users/ming/Sites/local-typeless/README.md`
- Create: `/Users/ming/Sites/local-typeless/Makefile`

- [ ] **Step 1: Initialize git repo**

Run in `/Users/ming/Sites/local-typeless`:

```bash
git init -b main
```

- [ ] **Step 2: Write .gitignore**

File: `.gitignore`

```gitignore
# Xcode
build/
DerivedData/
*.xcodeproj/
*.xcworkspace/
!default.xcworkspace
xcuserdata/
*.xcuserstate
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3

# Swift Package Manager
.build/
Packages/
Package.resolved
.swiftpm/

# macOS
.DS_Store

# User
.vscode/
.idea/

# Models cache (large)
Models/
```

- [ ] **Step 3: Write README.md**

File: `README.md`

```markdown
# local-typeless

Native macOS menu-bar dictation app. Offline speech-to-text (EN + ZH) with local LLM polish, inspired by Typeless.

## Build

    make build
    make test
    make run

## Requirements

- macOS 14+
- Xcode 15.3+ (Swift 5.9)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Docs

- [Design spec](docs/superpowers/specs/2026-04-22-local-typeless-design.md)
- [Phase 1 plan](docs/superpowers/plans/2026-04-22-local-typeless-phase1-core-loop.md)
```

- [ ] **Step 4: Write Makefile**

File: `Makefile`

```makefile
.PHONY: generate build test run clean

SCHEME = LocalTypeless
DEST = platform=macOS

generate:
	xcodegen generate

build: generate
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST)' -quiet

test: generate
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST)' -quiet

run: build
	open build/Debug/LocalTypeless.app

clean:
	rm -rf build DerivedData LocalTypeless.xcodeproj
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore README.md Makefile
git commit -m "chore: initialize repository with gitignore, README, and Makefile"
```

---

## Task 2: XcodeGen project configuration

**Files:**
- Create: `project.yml`
- Create: `LocalTypeless/Resources/Info.plist`

- [ ] **Step 1: Verify XcodeGen installed**

Run: `xcodegen --version`
Expected: version number printed. If missing: `brew install xcodegen`.

- [ ] **Step 2: Write project.yml**

File: `project.yml`

```yaml
name: LocalTypeless
options:
  bundleIdPrefix: com.localtypeless
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
  developmentLanguage: en
settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    ENABLE_USER_SCRIPT_SANDBOXING: NO
    SWIFT_STRICT_CONCURRENCY: complete
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: 6.29.0
targets:
  LocalTypeless:
    type: application
    platform: macOS
    sources:
      - path: LocalTypeless
    resources:
      - LocalTypeless/Resources
    info:
      path: LocalTypeless/Resources/Info.plist
      properties:
        LSUIElement: true
        NSMicrophoneUsageDescription: local-typeless needs microphone access to record your dictation audio.
        NSAccessibilityUsageDescription: local-typeless needs Accessibility access to inject transcribed text into the focused app and to capture your global hotkey.
        CFBundleDisplayName: local-typeless
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
    entitlements:
      path: LocalTypeless/Resources/LocalTypeless.entitlements
      properties:
        com.apple.security.app-sandbox: false
        com.apple.security.device.audio-input: true
    dependencies:
      - package: GRDB
  LocalTypelessTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: LocalTypelessTests
    dependencies:
      - target: LocalTypeless
```

- [ ] **Step 3: Create Info.plist placeholder**

File: `LocalTypeless/Resources/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

(XcodeGen merges the `info.properties` from `project.yml` into this file at generation time.)

- [ ] **Step 4: Create entitlements file**

File: `LocalTypeless/Resources/LocalTypeless.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <false/>
  <key>com.apple.security.device.audio-input</key>
  <true/>
</dict>
</plist>
```

- [ ] **Step 5: Create placeholder source + test so generate works**

File: `LocalTypeless/App/LocalTypelessApp.swift`

```swift
import SwiftUI

@main
struct LocalTypelessApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

File: `LocalTypelessTests/PlaceholderTests.swift`

```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func test_placeholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 6: Generate and verify build**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Run tests**

Run: `make test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add project.yml LocalTypeless/ LocalTypelessTests/
git commit -m "feat: scaffold XcodeGen project with GRDB dependency and macOS 14 target"
```

---

## Task 3: Logger utility

**Files:**
- Create: `LocalTypeless/Support/Logger.swift`

- [ ] **Step 1: Implement Logger**

File: `LocalTypeless/Support/Logger.swift`

```swift
import Foundation
import os

enum Log {
    static let subsystem = "com.localtypeless.app"
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let recorder = Logger(subsystem: subsystem, category: "recorder")
    static let asr = Logger(subsystem: subsystem, category: "asr")
    static let polish = Logger(subsystem: subsystem, category: "polish")
    static let injector = Logger(subsystem: subsystem, category: "injector")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let state = Logger(subsystem: subsystem, category: "state")
    static let menu = Logger(subsystem: subsystem, category: "menu")
}
```

- [ ] **Step 2: Build to verify**

Run: `make build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add LocalTypeless/Support/Logger.swift
git commit -m "feat: add os.Logger wrapper with per-category loggers"
```

---

## Task 4: DictationState enum + StateMachine (TDD)

**Files:**
- Create: `LocalTypeless/Core/DictationState.swift`
- Create: `LocalTypeless/Core/StateMachine.swift`
- Create: `LocalTypelessTests/StateMachineTests.swift`

- [ ] **Step 1: Write the failing test**

File: `LocalTypelessTests/StateMachineTests.swift`

```swift
import XCTest
@testable import LocalTypeless

@MainActor
final class StateMachineTests: XCTestCase {

    func test_initialStateIsIdle() {
        let sm = StateMachine()
        XCTAssertEqual(sm.state, .idle)
    }

    func test_toggleFromIdleStartsRecording() {
        let sm = StateMachine()
        sm.toggle()
        XCTAssertEqual(sm.state, .recording)
    }

    func test_toggleFromRecordingGoesToTranscribing() {
        let sm = StateMachine()
        sm.toggle()  // idle -> recording
        sm.toggle()  // recording -> transcribing
        XCTAssertEqual(sm.state, .transcribing)
    }

    func test_advanceFromTranscribingGoesToPolishing() {
        let sm = StateMachine()
        sm.toggle()
        sm.toggle()
        sm.advance()  // transcribing -> polishing
        XCTAssertEqual(sm.state, .polishing)
    }

    func test_advanceFromPolishingGoesToInjecting() {
        let sm = StateMachine()
        sm.toggle(); sm.toggle(); sm.advance()  // polishing
        sm.advance()  // injecting
        XCTAssertEqual(sm.state, .injecting)
    }

    func test_advanceFromInjectingReturnsToIdle() {
        let sm = StateMachine()
        sm.toggle(); sm.toggle(); sm.advance(); sm.advance()
        sm.advance()
        XCTAssertEqual(sm.state, .idle)
    }

    func test_failMovesToErrorFromAnyProcessingState() {
        let sm = StateMachine()
        sm.toggle(); sm.toggle()  // transcribing
        sm.fail(message: "boom")
        if case .error(let msg) = sm.state {
            XCTAssertEqual(msg, "boom")
        } else {
            XCTFail("expected error state, got \(sm.state)")
        }
    }

    func test_toggleFromErrorReturnsToIdle() {
        let sm = StateMachine()
        sm.fail(message: "x")
        sm.toggle()
        XCTAssertEqual(sm.state, .idle)
    }

    func test_toggleWhileTranscribingIsIgnored() {
        let sm = StateMachine()
        sm.toggle(); sm.toggle()  // transcribing
        sm.toggle()  // should be no-op
        XCTAssertEqual(sm.state, .transcribing)
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `make test`
Expected: build error "cannot find 'StateMachine' in scope".

- [ ] **Step 3: Implement DictationState**

File: `LocalTypeless/Core/DictationState.swift`

```swift
import Foundation

enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case polishing
    case injecting
    case error(String)
}
```

- [ ] **Step 4: Implement StateMachine**

File: `LocalTypeless/Core/StateMachine.swift`

```swift
import Foundation
import Observation

@MainActor
@Observable
final class StateMachine {
    private(set) var state: DictationState = .idle

    func toggle() {
        switch state {
        case .idle:
            state = .recording
            Log.state.info("idle -> recording")
        case .recording:
            state = .transcribing
            Log.state.info("recording -> transcribing")
        case .error:
            state = .idle
            Log.state.info("error -> idle")
        case .transcribing, .polishing, .injecting:
            Log.state.debug("toggle ignored in \(String(describing: self.state), privacy: .public)")
        }
    }

    func advance() {
        switch state {
        case .transcribing:
            state = .polishing
            Log.state.info("transcribing -> polishing")
        case .polishing:
            state = .injecting
            Log.state.info("polishing -> injecting")
        case .injecting:
            state = .idle
            Log.state.info("injecting -> idle")
        default:
            Log.state.debug("advance ignored in \(String(describing: self.state), privacy: .public)")
        }
    }

    func fail(message: String) {
        state = .error(message)
        Log.state.error("failed: \(message, privacy: .public)")
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `make test`
Expected: all `StateMachineTests` pass.

- [ ] **Step 6: Commit**

```bash
git add LocalTypeless/Core/DictationState.swift LocalTypeless/Core/StateMachine.swift LocalTypelessTests/StateMachineTests.swift
git commit -m "feat: add DictationState enum and StateMachine with full transition tests"
```

---

## Task 5: HotkeyBinding value type (TDD)

**Files:**
- Create: `LocalTypeless/Core/HotkeyBinding.swift`
- Create: `LocalTypelessTests/HotkeyBindingTests.swift`

- [ ] **Step 1: Write the failing test**

File: `LocalTypelessTests/HotkeyBindingTests.swift`

```swift
import XCTest
@testable import LocalTypeless

final class HotkeyBindingTests: XCTestCase {

    func test_defaultIsDoubleTapRightOption() {
        let b = HotkeyBinding.default
        XCTAssertEqual(b.trigger, .doubleTap)
        XCTAssertEqual(b.modifierOnly, .rightOption)
        XCTAssertNil(b.keyCode)
    }

    func test_roundTripsThroughUserDefaults() throws {
        let b = HotkeyBinding(
            keyCode: 2,  // "D"
            modifierMask: [.command, .shift],
            trigger: .press,
            modifierOnly: nil
        )
        let data = try JSONEncoder().encode(b)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)
        XCTAssertEqual(decoded, b)
    }

    func test_displayStringForComboIsReadable() {
        let b = HotkeyBinding(
            keyCode: 2,
            modifierMask: [.command, .shift],
            trigger: .press,
            modifierOnly: nil
        )
        XCTAssertEqual(b.displayString, "⌘⇧D")
    }

    func test_displayStringForModifierOnlyDoubleTap() {
        XCTAssertEqual(HotkeyBinding.default.displayString, "Double-tap Right ⌥")
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `make test`
Expected: build error "cannot find 'HotkeyBinding' in scope".

- [ ] **Step 3: Implement HotkeyBinding**

File: `LocalTypeless/Core/HotkeyBinding.swift`

```swift
import Foundation
import AppKit

struct HotkeyBinding: Codable, Equatable {

    enum Trigger: String, Codable { case press, doubleTap, longPress }

    enum ModifierOnly: String, Codable {
        case leftCommand, rightCommand
        case leftOption, rightOption
        case leftControl, rightControl
        case leftShift, rightShift
        case fn

        var displayName: String {
            switch self {
            case .leftCommand:  return "Left ⌘"
            case .rightCommand: return "Right ⌘"
            case .leftOption:   return "Left ⌥"
            case .rightOption:  return "Right ⌥"
            case .leftControl:  return "Left ⌃"
            case .rightControl: return "Right ⌃"
            case .leftShift:    return "Left ⇧"
            case .rightShift:   return "Right ⇧"
            case .fn:           return "fn"
            }
        }
    }

    /// Virtual key code, when this is a regular key+modifier combo. Nil for modifier-only bindings.
    let keyCode: UInt16?
    /// Modifier mask for key+modifier combos. Empty for modifier-only bindings.
    let modifierMask: NSEvent.ModifierFlags
    let trigger: Trigger
    /// Which modifier, if this is a modifier-only binding. Nil for key+modifier combos.
    let modifierOnly: ModifierOnly?

    static let `default` = HotkeyBinding(
        keyCode: nil,
        modifierMask: [],
        trigger: .doubleTap,
        modifierOnly: .rightOption
    )

    var displayString: String {
        if let mod = modifierOnly {
            let prefix: String = {
                switch trigger {
                case .press: return "Tap"
                case .doubleTap: return "Double-tap"
                case .longPress: return "Hold"
                }
            }()
            return "\(prefix) \(mod.displayName)"
        }
        var s = ""
        if modifierMask.contains(.control) { s += "⌃" }
        if modifierMask.contains(.option)  { s += "⌥" }
        if modifierMask.contains(.shift)   { s += "⇧" }
        if modifierMask.contains(.command) { s += "⌘" }
        if let kc = keyCode {
            s += Self.displayCharacter(for: kc) ?? "?"
        }
        return s
    }

    private static let keyCodeNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 45: "N", 46: "M", 49: "Space"
    ]

    static func displayCharacter(for keyCode: UInt16) -> String? {
        keyCodeNames[keyCode]
    }
}

extension NSEvent.ModifierFlags: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(UInt.self)
        self = NSEvent.ModifierFlags(rawValue: raw)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.rawValue)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `make test`
Expected: all `HotkeyBindingTests` pass.

- [ ] **Step 5: Commit**

```bash
git add LocalTypeless/Core/HotkeyBinding.swift LocalTypelessTests/HotkeyBindingTests.swift
git commit -m "feat: add HotkeyBinding with key+modifier and modifier-only triggers"
```

---

## Task 6: HotkeyManager (key+modifier path via Carbon)

**Files:**
- Create: `LocalTypeless/Core/HotkeyManager.swift`

This task is integration-heavy (Carbon C APIs). We validate manually in Task 12; unit testing Carbon event registration requires a full app run loop, which we skip for now.

- [ ] **Step 1: Implement HotkeyManager for key+modifier path**

File: `LocalTypeless/Core/HotkeyManager.swift`

```swift
import Foundation
import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {

    typealias ToggleHandler = () -> Void

    private var onToggle: ToggleHandler?
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonHandlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentBinding: HotkeyBinding?
    private var lastModifierPress: (key: HotkeyBinding.ModifierOnly, time: CFAbsoluteTime)?
    private static var sharedInstance: HotkeyManager?

    init() {
        Self.sharedInstance = self
    }

    deinit {
        tearDown()
    }

    func install(binding: HotkeyBinding, onToggle: @escaping ToggleHandler) {
        tearDown()
        self.onToggle = onToggle
        self.currentBinding = binding

        if binding.modifierOnly != nil {
            installEventTap(for: binding)
        } else if let keyCode = binding.keyCode {
            installCarbonHotkey(keyCode: keyCode, modifierMask: binding.modifierMask)
        } else {
            Log.hotkey.error("binding has neither keyCode nor modifierOnly")
        }
    }

    func tearDown() {
        if let ref = carbonHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonHotKeyRef = nil
        }
        if let h = carbonHandlerRef {
            RemoveEventHandler(h)
            carbonHandlerRef = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        currentBinding = nil
    }

    // MARK: - Carbon path (key + modifier)

    private func installCarbonHotkey(keyCode: UInt16, modifierMask: NSEvent.ModifierFlags) {
        let signature: FourCharCode = 0x4c544c53  // 'LTLS'
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async {
                HotkeyManager.sharedInstance?.onToggle?()
            }
            return noErr
        }, 1, &eventType, nil, &carbonHandlerRef)

        let carbonMods = Self.carbonModifiers(from: modifierMask)
        RegisterEventHotKey(UInt32(keyCode), carbonMods, hotKeyID,
                            GetApplicationEventTarget(), 0, &carbonHotKeyRef)
        Log.hotkey.info("carbon hotkey registered")
    }

    private static func carbonModifiers(from mask: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if mask.contains(.command) { m |= UInt32(cmdKey) }
        if mask.contains(.option)  { m |= UInt32(optionKey) }
        if mask.contains(.control) { m |= UInt32(controlKey) }
        if mask.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }

    // MARK: - CGEventTap path (modifier-only)

    private func installEventTap(for binding: HotkeyBinding) {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
            DispatchQueue.main.async {
                HotkeyManager.sharedInstance?.handleFlagsChanged(event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        ) else {
            Log.hotkey.error("failed to create event tap (need Input Monitoring permission)")
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.hotkey.info("event tap installed for modifier-only binding")
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        guard let binding = currentBinding, let target = binding.modifierOnly else { return }
        let targetKeyCode = Self.cgKeyCode(for: target)
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == targetKeyCode else { return }

        let now = CFAbsoluteTimeGetCurrent()
        switch binding.trigger {
        case .press:
            // fire on key-down only; flagsChanged doesn't distinguish directly — check if the modifier flag is set.
            if isModifierActive(for: target, flags: event.flags) {
                onToggle?()
            }
        case .doubleTap:
            if !isModifierActive(for: target, flags: event.flags) {
                // key-up — ignore
                return
            }
            if let last = lastModifierPress, last.key == target, now - last.time < 0.3 {
                lastModifierPress = nil
                onToggle?()
            } else {
                lastModifierPress = (target, now)
            }
        case .longPress:
            // key-down starts a timer; key-up cancels. Simplified: fire if modifier held 500 ms.
            if isModifierActive(for: target, flags: event.flags) {
                lastModifierPress = (target, now)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, let last = self.lastModifierPress, last.key == target else { return }
                    if CFAbsoluteTimeGetCurrent() - last.time >= 0.5 {
                        self.onToggle?()
                        self.lastModifierPress = nil
                    }
                }
            } else {
                lastModifierPress = nil
            }
        }
    }

    private static func cgKeyCode(for mod: HotkeyBinding.ModifierOnly) -> CGKeyCode {
        switch mod {
        case .leftCommand:  return 0x37
        case .rightCommand: return 0x36
        case .leftShift:    return 0x38
        case .rightShift:   return 0x3C
        case .leftOption:   return 0x3A
        case .rightOption:  return 0x3D
        case .leftControl:  return 0x3B
        case .rightControl: return 0x3E
        case .fn:           return 0x3F
        }
    }

    private func isModifierActive(for mod: HotkeyBinding.ModifierOnly, flags: CGEventFlags) -> Bool {
        switch mod {
        case .leftCommand, .rightCommand: return flags.contains(.maskCommand)
        case .leftShift, .rightShift:     return flags.contains(.maskShift)
        case .leftOption, .rightOption:   return flags.contains(.maskAlternate)
        case .leftControl, .rightControl: return flags.contains(.maskControl)
        case .fn:                         return flags.contains(.maskSecondaryFn)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `make build`
Expected: build succeeds. (Manual hotkey validation happens in Task 12.)

- [ ] **Step 3: Commit**

```bash
git add LocalTypeless/Core/HotkeyManager.swift
git commit -m "feat: add HotkeyManager with Carbon and CGEventTap paths for custom bindings"
```

---

## Task 7: AudioBuffer (TDD)

**Files:**
- Create: `LocalTypeless/Core/AudioBuffer.swift`
- Create: `LocalTypelessTests/AudioBufferTests.swift`

- [ ] **Step 1: Write the failing test**

File: `LocalTypelessTests/AudioBufferTests.swift`

```swift
import XCTest
@testable import LocalTypeless

final class AudioBufferTests: XCTestCase {

    func test_newBufferIsEmpty() {
        let b = AudioBuffer(maxSeconds: 120, sampleRate: 16_000)
        XCTAssertEqual(b.sampleCount, 0)
        XCTAssertEqual(b.durationSeconds, 0)
    }

    func test_appendIncreasesCount() {
        let b = AudioBuffer(maxSeconds: 120, sampleRate: 16_000)
        b.append([0.0, 0.1, 0.2, 0.3])
        XCTAssertEqual(b.sampleCount, 4)
    }

    func test_durationMatchesSampleRate() {
        let b = AudioBuffer(maxSeconds: 120, sampleRate: 16_000)
        b.append(Array(repeating: 0, count: 16_000))
        XCTAssertEqual(b.durationSeconds, 1.0, accuracy: 0.001)
    }

    func test_dropsOldestSamplesWhenExceedingMax() {
        let b = AudioBuffer(maxSeconds: 1, sampleRate: 16_000)
        b.append(Array(repeating: Float(1), count: 16_000))
        b.append(Array(repeating: Float(2), count: 8_000))
        XCTAssertEqual(b.sampleCount, 16_000)
        let snapshot = b.snapshot()
        XCTAssertEqual(snapshot.first, 1)
        XCTAssertEqual(snapshot.last, 2)
    }

    func test_resetEmptiesBuffer() {
        let b = AudioBuffer(maxSeconds: 1, sampleRate: 16_000)
        b.append([1, 2, 3])
        b.reset()
        XCTAssertEqual(b.sampleCount, 0)
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `make test`
Expected: build error "cannot find 'AudioBuffer' in scope".

- [ ] **Step 3: Implement AudioBuffer**

File: `LocalTypeless/Core/AudioBuffer.swift`

```swift
import Foundation

final class AudioBuffer {

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
```

- [ ] **Step 4: Run the tests**

Run: `make test`
Expected: `AudioBufferTests` pass.

- [ ] **Step 5: Commit**

```bash
git add LocalTypeless/Core/AudioBuffer.swift LocalTypelessTests/AudioBufferTests.swift
git commit -m "feat: add AudioBuffer ring buffer with fixed duration cap"
```

---

## Task 8: Recorder

**Files:**
- Create: `LocalTypeless/Core/Recorder.swift`

`AVAudioEngine` is hard to unit-test without a real audio device; we lean on manual verification in Task 12. The class is kept minimal so the surface to test later (once we have DI for the engine) is small.

- [ ] **Step 1: Implement Recorder**

File: `LocalTypeless/Core/Recorder.swift`

```swift
import Foundation
import AVFoundation

@MainActor
final class Recorder {

    private let engine = AVAudioEngine()
    private let buffer: AudioBuffer
    private var isRunning = false
    private let targetSampleRate: Double = 16_000

    init(buffer: AudioBuffer) {
        self.buffer = buffer
    }

    func start() throws {
        guard !isRunning else { return }
        buffer.reset()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterCreationFailed
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcm, _ in
            guard let self else { return }
            let outFrameCapacity = AVAudioFrameCount(
                Double(pcm.frameLength) * self.targetSampleRate / inputFormat.sampleRate
            )
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrameCapacity) else {
                return
            }
            var err: NSError?
            let status = converter.convert(to: outBuf, error: &err) { _, outStatus in
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
            self.buffer.append(samples)
        }

        try engine.start()
        isRunning = true
        Log.recorder.info("recording started")
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        Log.recorder.info("recording stopped: \(self.buffer.durationSeconds, privacy: .public) s captured")
    }

    enum RecorderError: Error {
        case formatCreationFailed
        case converterCreationFailed
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `make build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add LocalTypeless/Core/Recorder.swift
git commit -m "feat: add Recorder wrapping AVAudioEngine with 16kHz mono conversion"
```

---

## Task 9: ASRService protocol + StubASRService (TDD)

**Files:**
- Create: `LocalTypeless/Services/ASRService.swift`
- Create: `LocalTypeless/Services/StubASRService.swift`
- Create: `LocalTypelessTests/StubASRServiceTests.swift`

- [ ] **Step 1: Write the failing test**

File: `LocalTypelessTests/StubASRServiceTests.swift`

```swift
import XCTest
@testable import LocalTypeless

final class StubASRServiceTests: XCTestCase {

    func test_returnsFixedTranscriptWithProvidedLanguage() async throws {
        let svc = StubASRService(fixedText: "hello world", language: "en")
        let buf = AudioBuffer(maxSeconds: 1, sampleRate: 16_000)
        buf.append(Array(repeating: Float(0), count: 16_000))
        let t = try await svc.transcribe(buf)
        XCTAssertEqual(t.text, "hello world")
        XCTAssertEqual(t.language, "en")
    }

    func test_includesFullTextAsSingleSegment() async throws {
        let svc = StubASRService(fixedText: "你好，世界", language: "zh")
        let buf = AudioBuffer(maxSeconds: 1, sampleRate: 16_000)
        let t = try await svc.transcribe(buf)
        XCTAssertEqual(t.segments.count, 1)
        XCTAssertEqual(t.segments.first?.text, "你好，世界")
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `make test`
Expected: build error "cannot find 'StubASRService' in scope".

- [ ] **Step 3: Implement ASRService protocol and Transcript struct**

File: `LocalTypeless/Services/ASRService.swift`

```swift
import Foundation

struct Transcript: Equatable {
    struct Segment: Equatable {
        let text: String
        let startSeconds: Double
        let endSeconds: Double
    }

    let text: String
    let language: String   // BCP-47, e.g. "en", "zh"
    let segments: [Segment]
}

protocol ASRService: AnyObject {
    func transcribe(_ audio: AudioBuffer) async throws -> Transcript
}
```

- [ ] **Step 4: Implement StubASRService**

File: `LocalTypeless/Services/StubASRService.swift`

```swift
import Foundation

final class StubASRService: ASRService {
    private let fixedText: String
    private let language: String

    init(fixedText: String = "this is a stubbed transcript", language: String = "en") {
        self.fixedText = fixedText
        self.language = language
    }

    func transcribe(_ audio: AudioBuffer) async throws -> Transcript {
        try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms simulated work
        let seg = Transcript.Segment(
            text: fixedText,
            startSeconds: 0,
            endSeconds: audio.durationSeconds
        )
        return Transcript(text: fixedText, language: language, segments: [seg])
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `make test`
Expected: `StubASRServiceTests` pass.

- [ ] **Step 6: Commit**

```bash
git add LocalTypeless/Services/ASRService.swift LocalTypeless/Services/StubASRService.swift LocalTypelessTests/StubASRServiceTests.swift
git commit -m "feat: add ASRService protocol and StubASRService"
```

---

## Task 10: PolishService protocol + StubPolishService (TDD)

**Files:**
- Create: `LocalTypeless/Services/PolishService.swift`
- Create: `LocalTypeless/Services/StubPolishService.swift`
- Create: `LocalTypelessTests/StubPolishServiceTests.swift`

- [ ] **Step 1: Write the failing test**

File: `LocalTypelessTests/StubPolishServiceTests.swift`

```swift
import XCTest
@testable import LocalTypeless

final class StubPolishServiceTests: XCTestCase {

    func test_capitalizesAndAddsPeriod() async throws {
        let svc = StubPolishService()
        let t = Transcript(text: "hello world", language: "en", segments: [])
        let polished = try await svc.polish(t, prompt: "")
        XCTAssertEqual(polished, "Hello world.")
    }

    func test_preservesChineseUntouched() async throws {
        let svc = StubPolishService()
        let t = Transcript(text: "你好，世界", language: "zh", segments: [])
        let polished = try await svc.polish(t, prompt: "")
        XCTAssertEqual(polished, "你好，世界")
    }

    func test_removesTrivialFillerWordsEnglish() async throws {
        let svc = StubPolishService()
        let t = Transcript(text: "um hello uh world", language: "en", segments: [])
        let polished = try await svc.polish(t, prompt: "")
        XCTAssertEqual(polished, "Hello world.")
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `make test`
Expected: build error "cannot find 'StubPolishService' in scope".

- [ ] **Step 3: Implement PolishService protocol**

File: `LocalTypeless/Services/PolishService.swift`

```swift
import Foundation

protocol PolishService: AnyObject {
    func polish(_ transcript: Transcript, prompt: String) async throws -> String
}
```

- [ ] **Step 4: Implement StubPolishService**

File: `LocalTypeless/Services/StubPolishService.swift`

```swift
import Foundation

/// Phase-1 stub that performs trivial text cleanup without a model.
/// Replaced by an MLX-backed implementation in Phase 3.
final class StubPolishService: PolishService {

    private static let englishFillers: Set<String> = ["um", "uh", "like", "you", "know"]

    func polish(_ transcript: Transcript, prompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: 50_000_000)
        if transcript.language == "en" {
            return polishEnglish(transcript.text)
        } else {
            return transcript.text
        }
    }

    private func polishEnglish(_ raw: String) -> String {
        let words = raw.split(separator: " ").filter { w in
            !Self.englishFillers.contains(w.lowercased())
        }
        guard let first = words.first else { return "" }
        var rebuilt = first.prefix(1).uppercased() + first.dropFirst()
        for w in words.dropFirst() {
            rebuilt += " " + w
        }
        if !rebuilt.hasSuffix(".") && !rebuilt.hasSuffix("?") && !rebuilt.hasSuffix("!") {
            rebuilt += "."
        }
        return rebuilt
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `make test`
Expected: `StubPolishServiceTests` pass.

- [ ] **Step 6: Commit**

```bash
git add LocalTypeless/Services/PolishService.swift LocalTypeless/Services/StubPolishService.swift LocalTypelessTests/StubPolishServiceTests.swift
git commit -m "feat: add PolishService protocol and StubPolishService with English filler stripping"
```

---

## Task 11: TextInjector

**Files:**
- Create: `LocalTypeless/Services/TextInjector.swift`

Integration-level behavior (pasteboard + synthesized Cmd+V) is validated manually in Task 12.

- [ ] **Step 1: Implement TextInjector**

File: `LocalTypeless/Services/TextInjector.swift`

```swift
import Foundation
import AppKit

@MainActor
final class TextInjector {

    enum InjectionError: Error {
        case accessibilityDenied
    }

    func inject(_ text: String) async throws {
        let pb = NSPasteboard.general
        let previous = pb.pasteboardItems?.first?.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard AXIsProcessTrusted() else {
            Log.injector.warning("accessibility not trusted — leaving text on pasteboard")
            throw InjectionError.accessibilityDenied
        }

        postCommandV()

        try? await Task.sleep(nanoseconds: 150_000_000)
        if let previous {
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
        Log.injector.info("injected \(text.count, privacy: .public) chars")
    }

    private func postCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9  // "v"
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add LocalTypeless/Services/TextInjector.swift
git commit -m "feat: add TextInjector using NSPasteboard and synthesized Cmd+V"
```

---

## Task 12: HistoryStore protocol + SQLite implementation (TDD)

**Files:**
- Create: `LocalTypeless/Persistence/HistoryStore.swift`
- Create: `LocalTypeless/Persistence/SQLiteHistoryStore.swift`
- Create: `LocalTypelessTests/SQLiteHistoryStoreTests.swift`

- [ ] **Step 1: Write the failing test**

File: `LocalTypelessTests/SQLiteHistoryStoreTests.swift`

```swift
import XCTest
@testable import LocalTypeless

final class SQLiteHistoryStoreTests: XCTestCase {

    private func makeStore() throws -> SQLiteHistoryStore {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("history-\(UUID().uuidString).sqlite")
        return try SQLiteHistoryStore(path: tmp)
    }

    func test_insertAndFetchRow() throws {
        let store = try makeStore()
        let entry = DictationEntry(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationMs: 4200,
            rawTranscript: "um hello",
            polishedText: "Hello.",
            language: "en",
            targetAppBundleId: "com.apple.TextEdit",
            targetAppName: "TextEdit"
        )
        let id = try store.insert(entry)
        XCTAssertGreaterThan(id, 0)
        let fetched = try store.all()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.polishedText, "Hello.")
    }

    func test_allReturnsNewestFirst() throws {
        let store = try makeStore()
        let a = DictationEntry(startedAt: Date(timeIntervalSince1970: 1), durationMs: 0,
                               rawTranscript: "a", polishedText: "a", language: "en",
                               targetAppBundleId: nil, targetAppName: nil)
        let b = DictationEntry(startedAt: Date(timeIntervalSince1970: 2), durationMs: 0,
                               rawTranscript: "b", polishedText: "b", language: "en",
                               targetAppBundleId: nil, targetAppName: nil)
        _ = try store.insert(a)
        _ = try store.insert(b)
        let rows = try store.all()
        XCTAssertEqual(rows.first?.polishedText, "b")
        XCTAssertEqual(rows.last?.polishedText, "a")
    }

    func test_searchFiltersByText() throws {
        let store = try makeStore()
        _ = try store.insert(DictationEntry(
            startedAt: Date(), durationMs: 0,
            rawTranscript: "cat", polishedText: "Cat.", language: "en",
            targetAppBundleId: nil, targetAppName: nil
        ))
        _ = try store.insert(DictationEntry(
            startedAt: Date(), durationMs: 0,
            rawTranscript: "dog", polishedText: "Dog.", language: "en",
            targetAppBundleId: nil, targetAppName: nil
        ))
        let results = try store.search(query: "cat")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.polishedText, "Cat.")
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `make test`
Expected: build error "cannot find 'SQLiteHistoryStore' in scope".

- [ ] **Step 3: Implement HistoryStore protocol + model**

File: `LocalTypeless/Persistence/HistoryStore.swift`

```swift
import Foundation

struct DictationEntry: Equatable {
    var id: Int64?
    let startedAt: Date
    let durationMs: Int
    let rawTranscript: String
    let polishedText: String
    let language: String
    let targetAppBundleId: String?
    let targetAppName: String?

    init(
        id: Int64? = nil,
        startedAt: Date,
        durationMs: Int,
        rawTranscript: String,
        polishedText: String,
        language: String,
        targetAppBundleId: String?,
        targetAppName: String?
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.rawTranscript = rawTranscript
        self.polishedText = polishedText
        self.language = language
        self.targetAppBundleId = targetAppBundleId
        self.targetAppName = targetAppName
    }
}

protocol HistoryStore {
    @discardableResult
    func insert(_ entry: DictationEntry) throws -> Int64
    func all() throws -> [DictationEntry]
    func search(query: String) throws -> [DictationEntry]
    func delete(id: Int64) throws
}
```

- [ ] **Step 4: Implement SQLiteHistoryStore with GRDB**

File: `LocalTypeless/Persistence/SQLiteHistoryStore.swift`

```swift
import Foundation
import GRDB

final class SQLiteHistoryStore: HistoryStore {

    private let dbQueue: DatabaseQueue

    init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.dbQueue = try DatabaseQueue(path: path.path)
        try migrate()
    }

    private func migrate() throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "dictation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("started_at", .datetime).notNull()
                t.column("duration_ms", .integer).notNull()
                t.column("raw_transcript", .text).notNull()
                t.column("polished_text", .text).notNull()
                t.column("language", .text).notNull()
                t.column("target_app_bundle_id", .text)
                t.column("target_app_name", .text)
            }
            try db.create(index: "idx_dictation_started_at",
                          on: "dictation", columns: ["started_at"])
        }
        try m.migrate(dbQueue)
    }

    func insert(_ entry: DictationEntry) throws -> Int64 {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO dictation
                    (started_at, duration_ms, raw_transcript, polished_text,
                     language, target_app_bundle_id, target_app_name)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                entry.startedAt, entry.durationMs, entry.rawTranscript,
                entry.polishedText, entry.language,
                entry.targetAppBundleId, entry.targetAppName
            ])
            return db.lastInsertedRowID
        }
    }

    func all() throws -> [DictationEntry] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM dictation ORDER BY started_at DESC
            """).map(Self.decode)
        }
    }

    func search(query: String) throws -> [DictationEntry] {
        try dbQueue.read { db in
            let like = "%\(query)%"
            return try Row.fetchAll(db, sql: """
                SELECT * FROM dictation
                WHERE raw_transcript LIKE ? OR polished_text LIKE ?
                ORDER BY started_at DESC
            """, arguments: [like, like]).map(Self.decode)
        }
    }

    func delete(id: Int64) throws {
        _ = try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM dictation WHERE id = ?", arguments: [id])
        }
    }

    private static func decode(_ row: Row) -> DictationEntry {
        DictationEntry(
            id: row["id"],
            startedAt: row["started_at"],
            durationMs: row["duration_ms"],
            rawTranscript: row["raw_transcript"],
            polishedText: row["polished_text"],
            language: row["language"],
            targetAppBundleId: row["target_app_bundle_id"],
            targetAppName: row["target_app_name"]
        )
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `make test`
Expected: `SQLiteHistoryStoreTests` pass.

- [ ] **Step 6: Commit**

```bash
git add LocalTypeless/Persistence/ LocalTypelessTests/SQLiteHistoryStoreTests.swift
git commit -m "feat: add HistoryStore protocol and GRDB-backed SQLiteHistoryStore"
```

---

## Task 13: MenuBarController

**Files:**
- Create: `LocalTypeless/App/MenuBarController.swift`
- Create: `LocalTypeless/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Implement MenuBarController**

File: `LocalTypeless/App/MenuBarController.swift`

```swift
import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let stateMachine: StateMachine
    private let onOpenSettings: () -> Void
    private let onOpenHistory: () -> Void
    private let onUnloadModels: () -> Void
    private var observation: NSKeyValueObservation?

    init(
        stateMachine: StateMachine,
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onUnloadModels: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.stateMachine = stateMachine
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.onUnloadModels = onUnloadModels
        configureMenu()
        refreshIcon()
        startObserving()
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open History", action: #selector(openHistoryAction), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Unload Models", action: #selector(unloadAction), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit local-typeless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func startObserving() {
        withObservationTracking { _ = stateMachine.state } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshIcon()
                self?.startObserving()
            }
        }
    }

    private func refreshIcon() {
        let button = statusItem.button
        let (symbol, tooltip): (String, String) = {
            switch stateMachine.state {
            case .idle:         return ("mic", "local-typeless — idle")
            case .recording:    return ("record.circle.fill", "Recording…")
            case .transcribing: return ("waveform", "Transcribing…")
            case .polishing:    return ("sparkles", "Polishing…")
            case .injecting:    return ("keyboard", "Inserting…")
            case .error(let m): return ("exclamationmark.triangle", "Error: \(m)")
            }
        }()
        button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button?.toolTip = tooltip
    }

    @objc private func openSettingsAction() { onOpenSettings() }
    @objc private func openHistoryAction() { onOpenHistory() }
    @objc private func unloadAction() { onUnloadModels() }
}
```

- [ ] **Step 2: Create a placeholder AppIcon**

File: `LocalTypeless/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

```json
{
  "images": [
    { "idiom": "mac", "size": "16x16", "scale": "1x" },
    { "idiom": "mac", "size": "16x16", "scale": "2x" },
    { "idiom": "mac", "size": "32x32", "scale": "1x" },
    { "idiom": "mac", "size": "32x32", "scale": "2x" },
    { "idiom": "mac", "size": "128x128", "scale": "1x" },
    { "idiom": "mac", "size": "128x128", "scale": "2x" },
    { "idiom": "mac", "size": "256x256", "scale": "1x" },
    { "idiom": "mac", "size": "256x256", "scale": "2x" },
    { "idiom": "mac", "size": "512x512", "scale": "1x" },
    { "idiom": "mac", "size": "512x512", "scale": "2x" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

File: `LocalTypeless/Resources/Assets.xcassets/Contents.json`

```json
{
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 3: Build**

Run: `make build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add LocalTypeless/App/MenuBarController.swift LocalTypeless/Resources/Assets.xcassets
git commit -m "feat: add MenuBarController with SF Symbol icon states"
```

---

## Task 14: Skeleton SettingsView and HistoryView

**Files:**
- Create: `LocalTypeless/UI/SettingsView.swift`
- Create: `LocalTypeless/UI/HistoryView.swift`

- [ ] **Step 1: Write SettingsView skeleton**

File: `LocalTypeless/UI/SettingsView.swift`

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Form {
                Text("Hotkey configuration — coming in Phase 5")
            }
            .tabItem { Label("General", systemImage: "gear") }

            Form {
                Text("Model management — coming in Phase 2")
            }
            .tabItem { Label("Models", systemImage: "cpu") }
        }
        .padding(20)
        .frame(width: 480, height: 320)
    }
}
```

- [ ] **Step 2: Write HistoryView skeleton**

File: `LocalTypeless/UI/HistoryView.swift`

```swift
import SwiftUI

struct HistoryView: View {

    @State private var entries: [DictationEntry] = []
    let store: HistoryStore

    var body: some View {
        VStack(alignment: .leading) {
            Text("History").font(.title).padding(.bottom, 8)
            if entries.isEmpty {
                Text("No dictations yet.").foregroundStyle(.secondary)
            } else {
                List(entries, id: \.id) { e in
                    VStack(alignment: .leading) {
                        Text(e.polishedText).font(.body)
                        Text("\(e.language) · \(e.startedAt.formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(width: 560, height: 420)
        .task { reload() }
    }

    private func reload() {
        entries = (try? store.all()) ?? []
    }
}
```

- [ ] **Step 3: Build**

Run: `make build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add LocalTypeless/UI/SettingsView.swift LocalTypeless/UI/HistoryView.swift
git commit -m "feat: add skeleton SettingsView and HistoryView"
```

---

## Task 15: Wire the end-to-end loop in AppDelegate

**Files:**
- Create: `LocalTypeless/App/AppDelegate.swift`
- Modify: `LocalTypeless/App/LocalTypelessApp.swift`

- [ ] **Step 1: Replace placeholder LocalTypelessApp.swift**

File: `LocalTypeless/App/LocalTypelessApp.swift`

```swift
import SwiftUI

@main
struct LocalTypelessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 2: Implement AppDelegate**

File: `LocalTypeless/App/AppDelegate.swift`

```swift
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var hotkeyManager: HotkeyManager!
    private var recorder: Recorder!
    private var audioBuffer: AudioBuffer!
    private var stateMachine: StateMachine!
    private var asrService: ASRService!
    private var polishService: PolishService!
    private var textInjector: TextInjector!
    private var historyStore: HistoryStore!
    private var menuBarController: MenuBarController!

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var recordingStart: Date?
    private var focusedBundleId: String?
    private var focusedAppName: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        audioBuffer = AudioBuffer(maxSeconds: 120, sampleRate: 16_000)
        recorder = Recorder(buffer: audioBuffer)
        stateMachine = StateMachine()
        asrService = StubASRService()
        polishService = StubPolishService()
        textInjector = TextInjector()
        historyStore = Self.makeHistoryStore()

        menuBarController = MenuBarController(
            stateMachine: stateMachine,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenHistory: { [weak self] in self?.openHistory() },
            onUnloadModels: { [weak self] in self?.unloadModels() }
        )

        hotkeyManager = HotkeyManager()
        let binding = Self.loadBinding() ?? .default
        hotkeyManager.install(binding: binding) { [weak self] in
            self?.handleToggle()
        }

        Log.state.info("launched")
    }

    // MARK: - End-to-end loop

    private func handleToggle() {
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
            stateMachine.toggle()  // recording -> transcribing
            Task { await runPipeline() }

        case .error:
            stateMachine.toggle()  // -> idle

        default:
            break
        }
    }

    private func runPipeline() async {
        let startedAt = recordingStart ?? Date()
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)

        let transcript: Transcript
        do {
            transcript = try await asrService.transcribe(audioBuffer)
        } catch {
            stateMachine.fail(message: "ASR failed")
            return
        }

        stateMachine.advance()  // transcribing -> polishing

        let polished: String
        do {
            polished = try await polishService.polish(transcript, prompt: "")
        } catch {
            Log.polish.error("polish failed — using raw transcript")
            polished = transcript.text
        }

        stateMachine.advance()  // polishing -> injecting

        do {
            try await textInjector.inject(polished)
        } catch TextInjector.InjectionError.accessibilityDenied {
            Log.injector.warning("accessibility denied; polished text left on pasteboard")
        } catch {
            Log.injector.error("injection failed: \(String(describing: error), privacy: .public)")
        }

        let entry = DictationEntry(
            startedAt: startedAt,
            durationMs: durationMs,
            rawTranscript: transcript.text,
            polishedText: polished,
            language: transcript.language,
            targetAppBundleId: focusedBundleId,
            targetAppName: focusedAppName
        )
        try? historyStore.insert(entry)

        stateMachine.advance()  // injecting -> idle
    }

    private func captureFocusedApp() {
        let app = NSWorkspace.shared.frontmostApplication
        focusedBundleId = app?.bundleIdentifier
        focusedAppName = app?.localizedName
    }

    private func unloadModels() {
        // Phase 1 stubs hold no resident state; real implementations override in Phase 2/3.
        Log.menu.info("unload models requested")
    }

    // MARK: - Window management

    private func openSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let host = NSHostingController(rootView: SettingsView())
        let w = NSWindow(contentViewController: host)
        w.title = "Settings"
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openHistory() {
        if let w = historyWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let host = NSHostingController(rootView: HistoryView(store: historyStore))
        let w = NSWindow(contentViewController: host)
        w.title = "History"
        w.styleMask = [.titled, .closable, .resizable]
        w.center()
        w.isReleasedWhenClosed = false
        historyWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Persistence helpers

    private static func makeHistoryStore() -> HistoryStore {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask)[0]
            .appendingPathComponent("local-typeless", isDirectory: true)
        let dbURL = supportDir.appendingPathComponent("history.sqlite")
        do {
            return try SQLiteHistoryStore(path: dbURL)
        } catch {
            fatalError("failed to open history store: \(error)")
        }
    }

    private static func loadBinding() -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: "hotkeyBinding") else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }
}
```

- [ ] **Step 3: Build**

Run: `make build`
Expected: succeeds.

- [ ] **Step 4: Run full test suite**

Run: `make test`
Expected: all previously-green tests still pass.

- [ ] **Step 5: Commit**

```bash
git add LocalTypeless/App/
git commit -m "feat: wire AppDelegate with end-to-end dictation pipeline using stubbed services"
```

---

## Task 16: Manual verification

Not a commit-producing task; exercises the full app.

- [ ] **Step 1: Launch the app**

Run: `make run`
Expected: menu-bar icon appears (mic SF Symbol). App has no visible windows.

- [ ] **Step 2: Grant permissions**

On first record, macOS will prompt for Microphone. Grant it.
Open System Settings → Privacy & Security → Accessibility, and add `LocalTypeless.app`. Re-launch the app.
Also add it under Input Monitoring.

- [ ] **Step 3: Exercise the loop**

- Open TextEdit, click into a new document.
- Double-tap right Option.
- Icon should turn into a red record symbol.
- Speak a few seconds (anything — ASR is stubbed).
- Double-tap right Option again.
- Icon cycles through pulsing symbols, then inserts the stub string ("This is a stubbed transcript." after polish) into TextEdit.

Expected outcome: text appears, icon returns to idle, history window (opened from the menu) shows one new row with the correct target app bundle id.

- [ ] **Step 4: Verify history persistence**

Quit the app, re-launch, open History from the menu. The previous row should still be there.

- [ ] **Step 5: If verification passes, tag the phase**

```bash
git tag phase-1-complete
```

---

## Self-Review Checklist

### Spec coverage

| Spec section | Phase 1 task(s) | Status |
|--------------|-----------------|--------|
| §2 Goals — menu-bar app, hotkey, offline | 1, 2, 13, 15 | ✓ |
| §2 Goals — ASR EN+ZH | Deferred to Phase 2 (stub in Task 9) | ✓ (scoped out) |
| §2 Goals — local LLM polish | Deferred to Phase 3 (stub in Task 10) | ✓ (scoped out) |
| §2 Goals — text injection | 11, 15 | ✓ |
| §2 Goals — searchable history | 12, 14 | ✓ |
| §2 Goals — bilingual UI | Deferred to Phase 6 | ✓ (scoped out) |
| §3 Tech stack — XcodeGen, GRDB | 2, 12 | ✓ |
| §4 Architecture — protocols + swappable services | 9, 10, 12 | ✓ |
| §5.1 HotkeyManager — Carbon + CGEventTap + custom | 5, 6 | ✓ |
| §5.2 Recorder — 16 kHz mono via AVAudioEngine | 7, 8 | ✓ |
| §5.3 ASRService | 9 (stub) | ✓ |
| §5.4 PolishService | 10 (stub) | ✓ |
| §5.5 TextInjector — pasteboard + Cmd+V | 11 | ✓ |
| §5.6 HistoryStore — SQLite/GRDB | 12 | ✓ |
| §5.7 Menu-bar UI — icon states | 13 | ✓ |
| §5.8 Settings window | 14 (skeleton) | ✓ (skeleton only) |
| §5.9 History window | 14 | ✓ |
| §6 Data flow — full pipeline | 15 | ✓ |
| §7 Permissions — mic, accessibility, input monitoring | 2 (Info.plist), 16 (manual grant) | ✓ |
| §8 Error handling — ASR, polish, injection fallbacks | 15 (runPipeline) | ✓ |

### Follow-up phases (parked)

- **Phase 2:** Replace `StubASRService` with `WhisperKitASRService` (model download, language detection, streaming).
- **Phase 3:** Replace `StubPolishService` with `MLXPolishService` (Qwen2.5-3B, prompt templating, EN+ZH default prompts).
- **Phase 4:** Settings — hotkey record field, language mode, prompt editor, audio retention.
- **Phase 5:** Full bilingual UI via Xcode String Catalogs + CI test asserting translation coverage.
- **Phase 6:** Onboarding flow, permission guidance, model download UI.

### Placeholder scan

No TBDs, TODOs, or "add appropriate X" remain. Every task has concrete code.

### Type consistency

- `Transcript`, `Transcript.Segment`, `DictationState`, `HotkeyBinding`, `DictationEntry` all defined once in Tasks 4/5/9/12 and used consistently in Tasks 13/14/15.
- `ASRService` and `PolishService` protocol signatures match their stub implementations and the call sites in `AppDelegate.runPipeline()`.
- `HistoryStore` protocol matches usage in `HistoryView` and `AppDelegate`.
