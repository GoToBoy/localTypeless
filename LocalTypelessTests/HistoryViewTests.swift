import XCTest
import SwiftUI
import ViewInspector
@testable import LocalTypeless

@MainActor
final class HistoryViewTests: XCTestCase {

    func test_renders_title_and_empty_state() throws {
        let store = EmptyHistoryStore()
        let view = HistoryView(store: store)
        let tree = try view.inspect()
        XCTAssertNoThrow(try tree.find(text: "History"))
        XCTAssertNoThrow(try tree.find(text: "No dictations yet."))
    }
}

/// Minimal in-memory stub that always returns no entries, for empty-state tests.
/// HistoryView's `.task` reload consults `all()`; an empty array keeps us in the
/// empty state without spinning up a real SQLite file.
private final class EmptyHistoryStore: HistoryStore, @unchecked Sendable {
    func insert(_ entry: DictationEntry) throws -> Int64 { 0 }
    func all() throws -> [DictationEntry] { [] }
    func search(query: String) throws -> [DictationEntry] { [] }
    func delete(id: Int64) throws {}
}
