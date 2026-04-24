import XCTest
import SwiftUI
import ViewInspector
@testable import LocalTypeless

@MainActor
final class SettingsPromptsTabTests: XCTestCase {

    private func makeView(prompt: String = "") -> (SettingsPromptsTab, AppSettings) {
        let s = AppSettings(storage: InMemorySettingsStorage())
        s.polishPromptOverride = prompt
        return (SettingsPromptsTab(settings: s), s)
    }

    func test_reset_button_disabled_when_override_empty() throws {
        let (view, _) = makeView(prompt: "")
        let button = try view.inspect().find(button: "Reset to default")
        XCTAssertTrue(try button.isDisabled())
    }

    func test_reset_button_enabled_when_override_nonempty() throws {
        let (view, _) = makeView(prompt: "Custom prompt text")
        let button = try view.inspect().find(button: "Reset to default")
        XCTAssertFalse(try button.isDisabled())
    }

    func test_reset_button_clears_override() throws {
        let (view, settings) = makeView(prompt: "Something to clear")
        try view.inspect().find(button: "Reset to default").tap()
        XCTAssertEqual(settings.polishPromptOverride, "")
    }

    func test_two_default_disclosure_groups_render() throws {
        let (view, _) = makeView()
        let groups = try view.inspect().findAll(ViewType.DisclosureGroup.self)
        XCTAssertEqual(groups.count, 2)
    }
}
