import XCTest
import SwiftUI
import ViewInspector
@testable import LocalTypeless

@MainActor
final class SettingsAdvancedTabTests: XCTestCase {

    private func makeView(
        retention: Bool = false,
        asrStatus: ModelStatus = .notDownloaded,
        polishStatus: ModelStatus = .notDownloaded,
        onDownloadAsr: @escaping () -> Void = {},
        onDownloadPolish: @escaping () -> Void = {},
        onReopenOnboarding: @escaping () -> Void = {}
    ) -> (SettingsAdvancedTab, AppSettings, FirstRunState) {
        let settings = AppSettings(storage: InMemorySettingsStorage())
        settings.audioRetentionEnabled = retention
        let store = ModelStatusStore()
        store.set(asrStatus, for: .asrWhisperLargeV3Turbo)
        store.set(polishStatus, for: .polishQwen25_3bInstruct4bit)
        let firstRun = FirstRunState(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        firstRun.markOnboardingCompleted()
        let view = SettingsAdvancedTab(
            settings: settings,
            modelStatusStore: store,
            onDownloadAsr: onDownloadAsr,
            onDownloadPolish: onDownloadPolish,
            firstRunState: firstRun,
            onReopenOnboarding: onReopenOnboarding
        )
        return (view, settings, firstRun)
    }

    func test_retention_stepper_disabled_when_toggle_off() throws {
        let (view, _, _) = makeView(retention: false)
        let stepper = try view.inspect().find(ViewType.Stepper.self)
        XCTAssertTrue(try stepper.isDisabled())
    }

    func test_retention_stepper_enabled_when_toggle_on() throws {
        let (view, _, _) = makeView(retention: true)
        let stepper = try view.inspect().find(ViewType.Stepper.self)
        XCTAssertFalse(try stepper.isDisabled())
    }

    func test_asr_model_row_shows_download_when_not_ready() throws {
        let (view, _, _) = makeView(asrStatus: .notDownloaded)
        XCTAssertNoThrow(try view.inspect().find(text: "Not downloaded"))
        // Two Download buttons (ASR + polish), both non-ready.
        let downloads = try view.inspect().findAll(ViewType.Button.self) { button in
            (try? button.labelView().text().string()) == "Download"
        }
        XCTAssertEqual(downloads.count, 2)
    }

    func test_asr_model_row_shows_ready_label_when_resident() throws {
        let (view, _, _) = makeView(asrStatus: .resident, polishStatus: .notDownloaded)
        XCTAssertNoThrow(try view.inspect().find(text: "Ready"))
        // Only the polish row is still showing Download.
        let downloads = try view.inspect().findAll(ViewType.Button.self) { button in
            (try? button.labelView().text().string()) == "Download"
        }
        XCTAssertEqual(downloads.count, 1)
    }

    func test_download_button_fires_callback() throws {
        var asrDownloaded = false
        let (view, _, _) = makeView(onDownloadAsr: { asrDownloaded = true })
        let downloads = try view.inspect().findAll(ViewType.Button.self) { button in
            (try? button.labelView().text().string()) == "Download"
        }
        try downloads.first?.tap()
        XCTAssertTrue(asrDownloaded)
    }

    func test_reopen_welcome_tour_resets_first_run_and_invokes_callback() throws {
        var reopened = false
        let (view, _, firstRun) = makeView(onReopenOnboarding: { reopened = true })
        XCTAssertTrue(firstRun.onboardingCompleted)
        try view.inspect().find(button: String(localized: "Reopen welcome tour…")).tap()
        XCTAssertFalse(firstRun.onboardingCompleted)
        XCTAssertTrue(reopened)
    }

    func test_ui_language_picker_wired_to_settings_for_each_mode() throws {
        let (view, settings, _) = makeView()
        let picker = try view.inspect().find(ViewType.Picker.self)
        for mode in UILanguageMode.allCases {
            try picker.select(value: mode)
            XCTAssertEqual(settings.uiLanguageMode, mode)
        }
    }
}
