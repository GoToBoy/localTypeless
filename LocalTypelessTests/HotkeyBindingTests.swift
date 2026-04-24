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
            keyCode: 2,
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

    func test_conflictsWith_true_for_same_key_and_mods() {
        let a = HotkeyBinding(keyCode: 0x03, modifierMask: [.command, .shift],
                              trigger: .press, modifierOnly: nil)
        let b = HotkeyBinding(keyCode: 0x03, modifierMask: [.command, .shift],
                              trigger: .press, modifierOnly: nil)
        XCTAssertTrue(a.conflictsWith(b))
    }

    func test_conflictsWith_false_for_different_keys() {
        let a = HotkeyBinding(keyCode: 0x03, modifierMask: [.command, .shift],
                              trigger: .press, modifierOnly: nil)
        let b = HotkeyBinding(keyCode: 0x04, modifierMask: [.command, .shift],
                              trigger: .press, modifierOnly: nil)
        XCTAssertFalse(a.conflictsWith(b))
    }

    func test_conflictsWith_true_for_same_modifier_only() {
        let a = HotkeyBinding.default  // double-tap right Option
        let b = HotkeyBinding(keyCode: nil, modifierMask: [],
                              trigger: .doubleTap, modifierOnly: .rightOption)
        XCTAssertTrue(a.conflictsWith(b))
    }

    func test_conflictsWith_false_across_trigger_types_on_same_modifier() {
        let a = HotkeyBinding(keyCode: nil, modifierMask: [], trigger: .press,
                              modifierOnly: .rightOption)
        let b = HotkeyBinding(keyCode: nil, modifierMask: [], trigger: .doubleTap,
                              modifierOnly: .rightOption)
        XCTAssertFalse(a.conflictsWith(b))
    }
}
