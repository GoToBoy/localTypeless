import XCTest
import SwiftUI
import ViewInspector
@testable import LocalTypeless

@MainActor
final class OnboardingViewTests: XCTestCase {

    func test_continueButton_disabled_when_microphone_not_granted() throws {
        let mock = MockPermissionChecker(mic: .notDetermined)
        let view = OnboardingView(checker: mock, onContinue: {})
        let button = try view.inspect().find(button: String(localized: "Continue"))
        XCTAssertTrue(try button.isDisabled())
    }

    func test_continueButton_disabled_when_inputMonitoring_not_granted() throws {
        let mock = MockPermissionChecker(mic: .granted, input: .notDetermined)
        let view = OnboardingView(checker: mock, onContinue: {})
        let button = try view.inspect().find(button: String(localized: "Continue"))
        XCTAssertTrue(try button.isDisabled())
    }

    func test_continueButton_enabled_when_microphone_and_inputMonitoring_granted() throws {
        let mock = MockPermissionChecker(mic: .granted, input: .granted)
        let view = OnboardingView(checker: mock, onContinue: {})
        let button = try view.inspect().find(button: String(localized: "Continue"))
        XCTAssertFalse(try button.isDisabled())
    }

    func test_continueButton_invokes_callback_on_tap() throws {
        var invoked = false
        let mock = MockPermissionChecker(mic: .granted, input: .granted)
        let view = OnboardingView(checker: mock, onContinue: { invoked = true })
        try view.inspect().find(button: String(localized: "Continue")).tap()
        XCTAssertTrue(invoked)
    }

    func test_grant_button_disabled_when_already_granted() throws {
        let mock = MockPermissionChecker(mic: .granted, accessibility: .granted, input: .granted)
        let view = OnboardingView(checker: mock, onContinue: {})
        // Three rows each show a "Granted" button disabled when status == .granted.
        let grantedButtons = try view.inspect().findAll(ViewType.Button.self) { button in
            (try? button.labelView().text().string()) == String(localized: "Granted")
        }
        XCTAssertEqual(grantedButtons.count, 3)
        for button in grantedButtons {
            XCTAssertTrue(try button.isDisabled())
        }
    }

    func test_row_titles_localize() throws {
        let mock = MockPermissionChecker(mic: .denied)
        let view = OnboardingView(checker: mock, onContinue: {})
        let tree = try view.inspect()
        XCTAssertNoThrow(try tree.find(text: String(localized: "Microphone")))
        XCTAssertNoThrow(try tree.find(text: String(localized: "Input Monitoring")))
        XCTAssertNoThrow(try tree.find(text: String(localized: "Accessibility")))
    }
}

@MainActor
final class MockPermissionChecker: PermissionCheckerProtocol {
    var microphoneStatus: PermissionChecker.Status
    var accessibilityStatus: PermissionChecker.Status
    var inputMonitoringStatus: PermissionChecker.Status

    init(
        mic: PermissionChecker.Status = .notDetermined,
        accessibility: PermissionChecker.Status = .notDetermined,
        input: PermissionChecker.Status = .notDetermined
    ) {
        self.microphoneStatus = mic
        self.accessibilityStatus = accessibility
        self.inputMonitoringStatus = input
    }

    func requestMicrophoneIfNeeded() async -> PermissionChecker.Status {
        microphoneStatus
    }
}
