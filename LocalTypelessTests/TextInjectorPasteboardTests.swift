import AppKit
import XCTest
@testable import LocalTypeless

@MainActor
final class TextInjectorPasteboardTests: XCTestCase {
    func test_pasteboardSnapshotRestoresMultipleItemsAndNonStringPayloads() {
        let pasteboard = NSPasteboard(name: .init("LocalTypelessTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        let customType = NSPasteboard.PasteboardType("com.localtypeless.test.binary")
        let first = NSPasteboardItem()
        first.setString("hello", forType: .string)
        first.setData(Data([0x01, 0x02, 0x03]), forType: customType)

        let second = NSPasteboardItem()
        second.setString("{\\rtf1\\ansi hello}", forType: .rtf)

        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])

        let snapshot = TextInjector.capturePasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("replacement", forType: .string)

        TextInjector.restorePasteboard(pasteboard, snapshot: snapshot)

        let items = pasteboard.pasteboardItems
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual(items?[0].string(forType: .string), "hello")
        XCTAssertEqual(items?[0].data(forType: customType), Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(items?[1].string(forType: .rtf), "{\\rtf1\\ansi hello}")
    }
}
