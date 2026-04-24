import XCTest
import SwiftUI
import ViewInspector
@testable import LocalTypeless

@MainActor
final class SettingsViewTests: XCTestCase {

    private func makeView() -> SettingsView {
        let storage = InMemorySettingsStorage()
        let settings = AppSettings(storage: storage)
        let store = ModelStatusStore()
        let firstRun = FirstRunState(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return SettingsView(
            settings: settings,
            modelStatusStore: store,
            onDownloadAsr: {},
            onDownloadPolish: {},
            firstRunState: firstRun,
            onReopenOnboarding: {}
        )
    }

    func test_renders_three_tab_labels() throws {
        let view = makeView()
        let tree = try view.inspect()
        XCTAssertNoThrow(try tree.find(text: "General"))
        XCTAssertNoThrow(try tree.find(text: "Prompts"))
        XCTAssertNoThrow(try tree.find(text: "Advanced"))
    }
}
