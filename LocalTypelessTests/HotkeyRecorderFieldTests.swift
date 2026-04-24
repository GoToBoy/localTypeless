import XCTest
import SwiftUI
import ViewInspector
@testable import LocalTypeless

@MainActor
final class HotkeyRecorderFieldTests: XCTestCase {

    func test_shows_em_dash_when_no_keycode() throws {
        @State var binding = HotkeyBinding(
            keyCode: nil, modifierMask: [], trigger: .press, modifierOnly: nil
        )
        let field = HotkeyRecorderField(binding: $binding)
        XCTAssertNoThrow(try field.inspect().find(text: "—"))
        XCTAssertNoThrow(try field.inspect().find(text: "Record"))
    }

    func test_shows_binding_displayString_when_keycode_set() throws {
        let model = HotkeyBinding(
            keyCode: 0x03, modifierMask: [.command, .shift], trigger: .press, modifierOnly: nil
        )
        @State var binding = model
        let field = HotkeyRecorderField(binding: $binding)
        XCTAssertNoThrow(try field.inspect().find(text: model.displayString))
    }
}
