# Phase 5: Bilingual UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Ship full English + Simplified Chinese (`zh-Hans`) translations for every user-facing string in the app, driven by a single Xcode String Catalog (`Localizable.xcstrings`). Wire the `UILanguageMode` setting so users can switch UI language at runtime (with an app-relaunch caveat). Add a CI-style snapshot test that scans the source tree for localized keys and fails if any is missing a `zh-Hans` translation.

**Architecture:**
1. `LocalTypeless/Resources/Localizable.xcstrings` — single JSON catalog for both languages. Xcode's String Catalog UI edits it; we can also hand-edit JSON.
2. SwiftUI `Text(...)`, `Label(...)`, `Button(...)` with string literals automatically use Bundle-based lookup — no code change needed for the **keys** themselves.
3. AppKit `NSMenuItem(title:...)` and other imperative strings use `String(localized: "KEY")` so they participate in the same catalog.
4. A snapshot test scans `.swift` files for localized key usages and asserts each key exists in both `en` and `zh-Hans` "state: translated" entries in the `.xcstrings` JSON.
5. `AppSettings.uiLanguageMode` (already defined in Phase 4) applies by writing to `UserDefaults.standard`'s `AppleLanguages` key; Settings advises restart for full effect.

**Tech stack:** Swift 5.9+, SwiftUI + AppKit, Xcode 15+ String Catalogs, Foundation JSONDecoder, XCTest.

---

## Task 1: Create Localizable.xcstrings with all current strings

**Files:**
- Create: `LocalTypeless/Resources/Localizable.xcstrings`
- Modify: `project.yml` (add Resources to target sources)

**Goal:** Ship a JSON string catalog covering every user-facing literal currently in the app, with both `en` and `zh-Hans` entries.

- [ ] **Step 1.1:** Enumerate every user-facing string. Search the repo:
  - `Text("...")`, `Label("...")`, `Button("...")`, `.tag(... )` with literal `Text`, `Picker("...")`, `Toggle("...")`, `Section("...")`, `Menu(...)` with string args across `LocalTypeless/UI/**/*.swift`
  - `NSMenuItem(title: "...")` in `LocalTypeless/App/MenuBarController.swift`
  - Any `String(localized: "...")` already present (none expected on first pass)
  - Error `LocalizedError` subtypes' `errorDescription` literals across `LocalTypeless/Services/*.swift`

Catalog this set. Expect ~60–80 keys. Examples:
- `"Download speech model"` / `"下载语音模型"`
- `"~1.5 GB · offline after download"` / `"~1.5 GB · 下载后可离线使用"`
- `"Downloading… %@"` / `"正在下载… %@"` (format argument for percentage)
- `"Ready"` / `"已就绪"`
- `"Settings..."` / `"设置..."`
- `"Unload Models"` / `"卸载模型"`
- `"Quit local-typeless"` / `"退出 local-typeless"`
- `"Hotkey"` (section) / `"快捷键"`
- `"ASR language"` / `"语音识别语言"`
- `"Auto-detect"` / `"自动检测"`
- `"English only"` / `"仅英文"`
- `"Chinese only"` / `"仅中文"`
- `"Launch at login"` / `"登录时启动"`
- `"Modifier-only"` / `"仅修饰键"`
- `"Double-tap right ⌥"` / `"双击右 ⌥"`
- `"Trigger shortcut"` / `"触发快捷键"`
- `"Reset to default"` / `"恢复默认"`
- `"Record"` / `"录制"`
- `"Recording…"` / `"正在录制…"`
- `"local-typeless — idle"` / `"local-typeless — 空闲"`
- `"Keep recordings on disk"` / `"保留录音文件"`
- `"Transcription failed: %@"` / `"转录失败：%@"`
- `"No audio captured"` / `"未捕获到音频"`
- `"ASR model is not loaded"` / `"语音识别模型未加载"`
- `"Polish model is not loaded"` / `"润色模型未加载"`

(These are seed examples; enumerate the full set during implementation.)

- [ ] **Step 1.2:** Write `LocalTypeless/Resources/Localizable.xcstrings` using this schema:

```json
{
  "sourceLanguage": "en",
  "version": "1.0",
  "strings": {
    "Download speech model": {
      "localizations": {
        "en": {
          "stringUnit": { "state": "translated", "value": "Download speech model" }
        },
        "zh-Hans": {
          "stringUnit": { "state": "translated", "value": "下载语音模型" }
        }
      }
    },
    "Downloading… %@": {
      "localizations": {
        "en": {
          "stringUnit": { "state": "translated", "value": "Downloading… %@" }
        },
        "zh-Hans": {
          "stringUnit": { "state": "translated", "value": "正在下载… %@" }
        }
      }
    }
    // ... all other keys
  }
}
```

- [ ] **Step 1.3:** Update `project.yml` to include `LocalTypeless/Resources` in target sources as a resource folder:

```yaml
targets:
  LocalTypeless:
    sources:
      - LocalTypeless
      - path: LocalTypeless/Resources
        type: folder
```

(If `Resources` is already included generally via the `LocalTypeless` folder sweep, verify `.xcstrings` is picked up as a resource — you should see it in the Copy Bundle Resources build phase after `xcodegen generate`.)

- [ ] **Step 1.4:** Run `xcodegen generate && xcodebuild build -scheme LocalTypeless -destination 'platform=macOS' -quiet`. Build should succeed. No runtime change yet since code still uses English literals and SwiftUI matches them as-is.

- [ ] **Step 1.5:** Commit: `feat: add Localizable.xcstrings catalog with en + zh-Hans translations`

---

## Task 2: Convert imperative/AppKit strings to String(localized:)

**Files:** `LocalTypeless/App/MenuBarController.swift`, `LocalTypeless/Services/WhisperKitASRService.swift`, `LocalTypeless/Services/MLXPolishService.swift`, any other `.swift` using raw string literals for user-facing text outside SwiftUI.

**Goal:** Make every AppKit-facing or imperative string go through `NSLocalizedString` (via `String(localized:)`) so the snapshot test in Task 4 can discover them, and so they actually localize at runtime.

- [ ] **Step 2.1:** In `MenuBarController.configureMenu()`, replace every `NSMenuItem(title: "X", ...)` with:

```swift
NSMenuItem(title: String(localized: "X"), action: ..., keyEquivalent: "")
```

And the inline concatenation `"\(name): \(status.displayLabel)"` becomes a format key:

```swift
NSMenuItem(
    title: String(localized: "\(name): \(status.displayLabel)"),
    action: nil, keyEquivalent: ""
)
```

Swift 5.9+ string interpolation in `String(localized:)` produces a key like `"%@: %@"` with `name` and `displayLabel` substituted. Catalog that format key, e.g. `"%@: %@"` → `"%@：%@"` for `zh-Hans` (fullwidth colon).

Better: split into two keys so translators can reorder if needed:
```swift
let label = String(
    localized: "\(name): \(status.displayLabel)",
    defaultValue: "\(name): \(status.displayLabel)"
)
```

Document the simplest pattern the team adopts.

- [ ] **Step 2.2:** Update `MenuBarController.refreshIcon`:

```swift
let (symbol, tooltip): (String, String) = {
    switch stateMachine.state {
    case .idle:         return ("mic", String(localized: "local-typeless — idle"))
    case .recording:    return ("record.circle.fill", String(localized: "Recording…"))
    case .transcribing: return ("waveform", String(localized: "Transcribing…"))
    case .polishing:    return ("sparkles", String(localized: "Polishing…"))
    case .injecting:    return ("keyboard", String(localized: "Inserting…"))
    case .error(let m): return ("exclamationmark.triangle",
                                String(localized: "Error: \(m)"))
    }
}()
```

- [ ] **Step 2.3:** Update `MenuBarController.ModelStatus.displayLabel` to return localized strings:

```swift
private extension ModelStatus {
    var displayLabel: String {
        switch self {
        case .notDownloaded:          return String(localized: "not downloaded")
        case .downloading(let p):     return String(localized: "downloading (\(Int(p * 100))%)")
        case .downloaded:             return String(localized: "downloaded")
        case .loading:                return String(localized: "loading…")
        case .resident:               return String(localized: "ready")
        case .failed(let message):    return String(localized: "failed: \(message)")
        }
    }
}
```

- [ ] **Step 2.4:** Convert `LocalizedError.errorDescription` cases in `WhisperKitASRError`, `MLXPolishError`, and any other error enums to use `String(localized:)` so error messages shown in UI localize.

Example for `WhisperKitASRError`:
```swift
var errorDescription: String? {
    switch self {
    case .modelNotReady:      return String(localized: "ASR model is not loaded")
    case .emptyAudio:         return String(localized: "No audio captured")
    case .transcriptionFailed(let m):
        return String(localized: "Transcription failed: \(m)")
    }
}
```

- [ ] **Step 2.5:** Xcode-regenerate and build. Quick manual sanity: launch the app; UI should still look English because the app's system locale default + fallback to source language.

- [ ] **Step 2.6:** Commit: `feat: route AppKit and error strings through String(localized:) for i18n`

---

## Task 3: Wire UILanguageMode runtime switch

**Files:** `LocalTypeless/Settings/AppSettings.swift` (modify slightly), `LocalTypeless/App/AppDelegate.swift` (modify), `LocalTypeless/UI/SettingsAdvancedTab.swift` (wire picker + restart note).

**Goal:** When the user picks a UI language in Settings, write `AppleLanguages` to `UserDefaults.standard` and surface a "Restart app to apply" note. On app launch, `AppleLanguages` is read by the Foundation loader for string resolution; manually-applied changes take effect on next launch.

**Rationale:** Runtime swapping of Bundle's localization is brittle (many views cache strings). Requiring a restart is honest and simple. Document this in the UI copy.

- [ ] **Step 3.1:** Add a static helper on `AppSettings`:

```swift
extension AppSettings {
    /// Apply the persisted UI language preference to `UserDefaults.standard`
    /// so Foundation uses it on next launch. `.system` removes the override.
    static func applyUILanguagePreference(_ mode: UILanguageMode) {
        let key = "AppleLanguages"
        switch mode {
        case .system:
            UserDefaults.standard.removeObject(forKey: key)
        case .en:
            UserDefaults.standard.set(["en"], forKey: key)
        case .zhHans:
            UserDefaults.standard.set(["zh-Hans"], forKey: key)
        }
    }
}
```

- [ ] **Step 3.2:** In `AppDelegate.applicationDidFinishLaunching(_:)`, right after creating `settings`:

```swift
AppSettings.applyUILanguagePreference(settings.uiLanguageMode)
```

This ensures the override is set for THIS launch session (even though the first resources lookup may have already happened — this line matters for subsequent lookups triggered by late-binding views).

- [ ] **Step 3.3:** Add observation to `startObservingSettings()` so changes are persisted mid-session:

```swift
withObservationTracking {
    _ = settings.hotkeyBinding
    _ = settings.asrLanguageMode
    _ = settings.launchAtLogin
    _ = settings.uiLanguageMode
} onChange: { [weak self] in
    Task { @MainActor in
        guard let self else { return }
        AppSettings.applyUILanguagePreference(self.settings.uiLanguageMode)
        self.applySettingsChange()
    }
}
```

(Adapt to the existing structure — current code already has `applySettingsChange()` hook.)

- [ ] **Step 3.4:** Update `SettingsAdvancedTab` UI to replace the stubbed UI language picker with a real one + restart note:

```swift
Section(String(localized: "Interface language")) {
    Picker(String(localized: "Language"), selection: $settings.uiLanguageMode) {
        Text("System").tag(UILanguageMode.system)
        Text("English").tag(UILanguageMode.en)
        Text("简体中文").tag(UILanguageMode.zhHans)
    }
    Text(String(localized: "Restart the app to see the change everywhere."))
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 3.5:** Add the new keys ("Interface language", "Language", "System", "English", "简体中文", "Restart the app to see the change everywhere.") to `Localizable.xcstrings`.

- [ ] **Step 3.6:** Build + manual test:
1. Launch; Settings → Advanced → Language → "简体中文" → Quit → Launch → menu bar should show Chinese labels.
2. Switch back to "System" → relaunch → back to system locale.

- [ ] **Step 3.7:** Commit: `feat: wire UILanguageMode to AppleLanguages override with restart note`

---

## Task 4: Snapshot test for translation coverage (TDD)

**Files:** Create `LocalTypelessTests/LocalizationCoverageTests.swift`. No production code changes.

**Goal:** Scan every `.swift` under `LocalTypeless/` for localized key usages (`String(localized: "X")`, `Text("X")`, `Label("X", systemImage: ...)`, etc.), parse `Localizable.xcstrings`, assert every discovered key has both `en` and `zh-Hans` translations with state "translated".

- [ ] **Step 4.1:** Write the test:

```swift
import XCTest

final class LocalizationCoverageTests: XCTestCase {

    func test_every_localized_key_has_en_and_zhHans() throws {
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // LocalTypelessTests/
            .deletingLastPathComponent()   // repo root

        // 1. Collect keys from source
        let sourceRoot = projectRoot.appendingPathComponent("LocalTypeless")
        let keys = try collectLocalizedKeys(under: sourceRoot)
        XCTAssertGreaterThan(keys.count, 10, "expected more than 10 localized keys, got \(keys.count)")

        // 2. Load catalog
        let catalogURL = sourceRoot.appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalog.self, from: data)

        // 3. Assert coverage
        var missingEn: [String] = []
        var missingZh: [String] = []
        for key in keys.sorted() {
            guard let entry = catalog.strings[key] else {
                missingEn.append(key)
                missingZh.append(key)
                continue
            }
            if entry.localizations["en"]?.stringUnit.state != "translated" {
                missingEn.append(key)
            }
            if entry.localizations["zh-Hans"]?.stringUnit.state != "translated" {
                missingZh.append(key)
            }
        }

        XCTAssertTrue(missingEn.isEmpty, "Missing en translations: \(missingEn)")
        XCTAssertTrue(missingZh.isEmpty, "Missing zh-Hans translations: \(missingZh)")
    }

    // MARK: - Support types

    private struct StringCatalog: Decodable {
        let strings: [String: Entry]

        struct Entry: Decodable {
            let localizations: [String: Localization]
        }

        struct Localization: Decodable {
            let stringUnit: StringUnit
        }

        struct StringUnit: Decodable {
            let state: String
            let value: String
        }
    }

    /// Scan .swift files for static string literals used in localized APIs.
    private func collectLocalizedKeys(under root: URL) throws -> Set<String> {
        var keys: Set<String> = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw NSError(domain: "LocalizationCoverageTests", code: 1)
        }

        let patterns: [NSRegularExpression] = [
            // String(localized: "...")
            try NSRegularExpression(pattern: #"String\(localized:\s*"([^"\\]*(?:\\.[^"\\]*)*)""#),
            // Text("..."), Label("..."), Button("..."), Section("..."), Picker("..."), Toggle("...")
            try NSRegularExpression(pattern: #"(?:Text|Label|Button|Section|Picker|Toggle)\(\s*"([^"\\]*(?:\\.[^"\\]*)*)""#),
            // NSMenuItem(title: "...")
            try NSRegularExpression(pattern: #"NSMenuItem\(title:\s*"([^"\\]*(?:\\.[^"\\]*)*)""#),
            // menu.addItem(withTitle: "...")
            try NSRegularExpression(pattern: #"addItem\(withTitle:\s*"([^"\\]*(?:\\.[^"\\]*)*)""#),
        ]

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for regex in patterns {
                regex.enumerateMatches(in: source, range: range) { match, _, _ in
                    guard let match, match.numberOfRanges >= 2,
                          let r = Range(match.range(at: 1), in: source) else { return }
                    let key = String(source[r])
                    // Skip obvious non-localizable: single char, whitespace, SF Symbol names
                    let looksLikeSymbol = key.allSatisfy {
                        $0.isLetter || $0.isNumber || $0 == "." || $0 == "_"
                    } && !key.contains(" ")
                    if !key.isEmpty && !looksLikeSymbol {
                        keys.insert(key)
                    }
                }
            }
        }
        return keys
    }
}
```

- [ ] **Step 4.2:** Run the test. It should PASS if Task 1 + 2 + 3 correctly populated the catalog. If it fails with missing keys, add them to the catalog and re-run. Repeat until green.

- [ ] **Step 4.3:** Commit: `test: add localization coverage snapshot test for en + zh-Hans`

---

## Task 5: Final review + tag

- [ ] **Step 5.1:** Full test run. Expect 48 total (47 + 1 new coverage test), 5 skipped, 43 pass.

- [ ] **Step 5.2:** Manual smoke:
- Launch app → menu bar labels in system language
- Settings → Advanced → Language → 简体中文 → Quit → Launch → menu bar labels are Chinese
- Open Settings → all labels in Chinese
- Trigger a dictation → error paths (e.g., no audio) surface in Chinese if model isn't ready
- Switch back to English → Quit → Launch → restored

- [ ] **Step 5.3:** Tag: `git tag phase-5-complete`

---

## Self-review checklist

- **Spec coverage §2 (bilingual UI):** Full translation of UI via Xcode String Catalog ✅ (Task 1, 2).
- **Spec coverage §8 (runtime language switch):** UI language mode persists + applies via AppleLanguages override ✅ (Task 3); honest about restart requirement.
- **Spec coverage §9.8 (i18n snapshot test):** Coverage test present ✅ (Task 4).
- **Placeholders:** None. Default keys enumerated seed-style for implementer to expand — plan instructs exhaustive enumeration as Step 1.1.
- **Type consistency:** `UILanguageMode` cases (`system`, `en`, `zhHans`) match `AppSettings` definition from Phase 4.
- **Tests:** 1 new test added (coverage). No new production unit tests (UI localization is surface-level).
- **Out of scope:** Pluralization rules, regional variants (en-GB, zh-Hant), right-to-left layouts — none needed for current scope.
