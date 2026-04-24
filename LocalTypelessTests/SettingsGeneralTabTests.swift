import XCTest
import SwiftUI
import ViewInspector
@testable import LocalTypeless

@MainActor
final class SettingsGeneralTabTests: XCTestCase {

    private func makeView(_ settings: AppSettings? = nil) -> (SettingsGeneralTab, AppSettings) {
        let s = settings ?? AppSettings(storage: InMemorySettingsStorage())
        return (SettingsGeneralTab(settings: s), s)
    }

    func test_renders_three_sections() throws {
        let (view, _) = makeView()
        let tree = try view.inspect()
        XCTAssertNoThrow(try tree.find(text: "Hotkey"))
        XCTAssertNoThrow(try tree.find(text: "Speech"))
        XCTAssertNoThrow(try tree.find(text: "Startup"))
    }

    func test_asr_language_picker_lists_three_options() throws {
        let (view, _) = makeView()
        let tree = try view.inspect()
        XCTAssertNoThrow(try tree.find(text: "Auto-detect"))
        XCTAssertNoThrow(try tree.find(text: "English only"))
        XCTAssertNoThrow(try tree.find(text: "Chinese only"))
    }

    func test_launch_at_login_toggle_bound_to_settings() throws {
        let (view, settings) = makeView()
        let toggle = try view.inspect().find(ViewType.Toggle.self)
        XCTAssertFalse(settings.launchAtLogin)
        try toggle.tap()
        XCTAssertTrue(settings.launchAtLogin)
    }

    func test_hotkey_and_modifier_only_rows_present() throws {
        let (view, _) = makeView()
        let tree = try view.inspect()
        XCTAssertNoThrow(try tree.find(text: "Trigger shortcut"))
        XCTAssertNoThrow(try tree.find(text: "Modifier-only"))
    }
}
