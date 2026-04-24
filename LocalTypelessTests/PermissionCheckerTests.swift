import XCTest
@testable import LocalTypeless

@MainActor
final class PermissionCheckerTests: XCTestCase {

    func test_all_statuses_return_valid_values() {
        let checker = PermissionChecker()
        let mic = checker.microphoneStatus
        XCTAssertTrue([.granted, .denied, .notDetermined].contains(mic))
        let ax = checker.accessibilityStatus
        XCTAssertTrue([.granted, .denied, .notDetermined].contains(ax))
        let hid = checker.inputMonitoringStatus
        XCTAssertTrue([.granted, .denied, .notDetermined].contains(hid))
    }

    func test_deepLink_urls_are_valid() {
        XCTAssertNotNil(PermissionChecker.systemSettingsURL(for: .microphone))
        XCTAssertNotNil(PermissionChecker.systemSettingsURL(for: .accessibility))
        XCTAssertNotNil(PermissionChecker.systemSettingsURL(for: .inputMonitoring))
    }
}
