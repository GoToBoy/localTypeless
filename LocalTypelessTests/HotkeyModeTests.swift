import XCTest
@testable import LocalTypeless

final class HotkeyModeTests: XCTestCase {

    func test_toggle_isSupportedForEveryBinding() {
        let carbon = HotkeyBinding(
            keyCode: 9, modifierMask: [.command, .shift],
            trigger: .press, modifierOnly: nil)
        let modPress = HotkeyBinding(
            keyCode: nil, modifierMask: [],
            trigger: .press, modifierOnly: .fn)
        let modDouble = HotkeyBinding(
            keyCode: nil, modifierMask: [],
            trigger: .doubleTap, modifierOnly: .rightOption)

        XCTAssertTrue(HotkeyMode.toggle.isSupported(by: carbon))
        XCTAssertTrue(HotkeyMode.toggle.isSupported(by: modPress))
        XCTAssertTrue(HotkeyMode.toggle.isSupported(by: modDouble))
    }

    func test_pushToTalk_onlySupportedByModifierOnlyPress() {
        let carbon = HotkeyBinding(
            keyCode: 9, modifierMask: [.command, .shift],
            trigger: .press, modifierOnly: nil)
        let modPress = HotkeyBinding(
            keyCode: nil, modifierMask: [],
            trigger: .press, modifierOnly: .fn)
        let modDouble = HotkeyBinding(
            keyCode: nil, modifierMask: [],
            trigger: .doubleTap, modifierOnly: .rightOption)
        let modLong = HotkeyBinding(
            keyCode: nil, modifierMask: [],
            trigger: .longPress, modifierOnly: .rightControl)

        XCTAssertFalse(HotkeyMode.pushToTalk.isSupported(by: carbon))
        XCTAssertTrue(HotkeyMode.pushToTalk.isSupported(by: modPress))
        XCTAssertFalse(HotkeyMode.pushToTalk.isSupported(by: modDouble))
        XCTAssertFalse(HotkeyMode.pushToTalk.isSupported(by: modLong))
    }

    func test_effective_fallsBackToToggleOnUnsupportedBinding() {
        let carbon = HotkeyBinding(
            keyCode: 9, modifierMask: [.command, .shift],
            trigger: .press, modifierOnly: nil)
        XCTAssertEqual(HotkeyMode.pushToTalk.effective(for: carbon), .toggle)

        let modPress = HotkeyBinding(
            keyCode: nil, modifierMask: [],
            trigger: .press, modifierOnly: .fn)
        XCTAssertEqual(HotkeyMode.pushToTalk.effective(for: modPress), .pushToTalk)
        XCTAssertEqual(HotkeyMode.toggle.effective(for: modPress), .toggle)
    }
}
