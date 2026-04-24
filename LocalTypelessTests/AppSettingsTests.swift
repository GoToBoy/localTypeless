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
        XCTAssertEqual(s.hotkeyMode, .toggle)
        XCTAssertEqual(s.asrLanguageMode, .auto)
        XCTAssertEqual(s.uiLanguageMode, .system)
        XCTAssertEqual(s.polishPromptOverride, "")
        XCTAssertTrue(s.audioRetentionEnabled == false)
        XCTAssertEqual(s.audioRetentionDays, 7)
        XCTAssertEqual(s.launchAtLogin, false)
        XCTAssertEqual(s.pasteMethod, .cgEvent)
        XCTAssertTrue(s.preserveClipboard)
        XCTAssertFalse(s.pauseMediaDuringRecording)
    }

    func test_newPrefsPersist() {
        let storage = InMemorySettingsStorage()
        let first = AppSettings(storage: storage)
        first.hotkeyMode = .pushToTalk
        first.pasteMethod = .appleScript
        first.preserveClipboard = false
        first.pauseMediaDuringRecording = true

        let second = AppSettings(storage: storage)
        XCTAssertEqual(second.hotkeyMode, .pushToTalk)
        XCTAssertEqual(second.pasteMethod, .appleScript)
        XCTAssertFalse(second.preserveClipboard)
        XCTAssertTrue(second.pauseMediaDuringRecording)
    }

    func test_writes_persist() {
        let (s, storage) = makeSettings()
        s.asrLanguageMode = .en
        s.polishPromptOverride = "Custom prompt"
        XCTAssertEqual(storage.string(forKey: "polishPromptOverride"), "Custom prompt")
        XCTAssertEqual(storage.string(forKey: "asrLanguageMode"), "en")
    }

    func test_hotkey_binding_roundtrips() {
        let storage = InMemorySettingsStorage()
        let b = HotkeyBinding(keyCode: 0x03, modifierMask: [.command, .shift],
                               trigger: .press, modifierOnly: nil)
        let first = AppSettings(storage: storage)
        first.hotkeyBinding = b
        let second = AppSettings(storage: storage)
        XCTAssertEqual(second.hotkeyBinding, b)
    }

    func test_resetPolishPrompt_clears_override() {
        let (s, _) = makeSettings()
        s.polishPromptOverride = "Do the thing"
        s.resetPolishPrompt()
        XCTAssertEqual(s.polishPromptOverride, "")
    }
}
