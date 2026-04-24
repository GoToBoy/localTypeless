import XCTest
@testable import LocalTypeless

final class SQLiteHistoryStoreTests: XCTestCase {

    private func makeStore() throws -> SQLiteHistoryStore {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("history-\(UUID().uuidString).sqlite")
        return try SQLiteHistoryStore(path: tmp)
    }

    func test_insertAndFetchRow() throws {
        let store = try makeStore()
        let entry = DictationEntry(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationMs: 4200,
            rawTranscript: "um hello",
            polishedText: "Hello.",
            language: "en",
            targetAppBundleId: "com.apple.TextEdit",
            targetAppName: "TextEdit"
        )
        let id = try store.insert(entry)
        XCTAssertGreaterThan(id, 0)
        let fetched = try store.all()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.polishedText, "Hello.")
    }

    func test_allReturnsNewestFirst() throws {
        let store = try makeStore()
        let a = DictationEntry(startedAt: Date(timeIntervalSince1970: 1), durationMs: 0,
                               rawTranscript: "a", polishedText: "a", language: "en",
                               targetAppBundleId: nil, targetAppName: nil)
        let b = DictationEntry(startedAt: Date(timeIntervalSince1970: 2), durationMs: 0,
                               rawTranscript: "b", polishedText: "b", language: "en",
                               targetAppBundleId: nil, targetAppName: nil)
        _ = try store.insert(a)
        _ = try store.insert(b)
        let rows = try store.all()
        XCTAssertEqual(rows.first?.polishedText, "b")
        XCTAssertEqual(rows.last?.polishedText, "a")
    }

    func test_searchFiltersByText() throws {
        let store = try makeStore()
        _ = try store.insert(DictationEntry(
            startedAt: Date(), durationMs: 0,
            rawTranscript: "cat", polishedText: "Cat.", language: "en",
            targetAppBundleId: nil, targetAppName: nil
        ))
        _ = try store.insert(DictationEntry(
            startedAt: Date(), durationMs: 0,
            rawTranscript: "dog", polishedText: "Dog.", language: "en",
            targetAppBundleId: nil, targetAppName: nil
        ))
        let results = try store.search(query: "cat")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.polishedText, "Cat.")
    }
}
