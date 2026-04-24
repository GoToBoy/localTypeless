import XCTest
@testable import LocalTypeless

@MainActor
final class ModelStatusStoreTests: XCTestCase {

    func test_defaults_to_not_downloaded() {
        let store = ModelStatusStore()
        XCTAssertEqual(store.status(for: .asrWhisperLargeV3Turbo), .notDownloaded)
    }

    func test_set_updates_status() {
        let store = ModelStatusStore()
        store.set(.downloading(progress: 0.42), for: .asrWhisperLargeV3Turbo)
        if case .downloading(let p) = store.status(for: .asrWhisperLargeV3Turbo) {
            XCTAssertEqual(p, 0.42, accuracy: 0.001)
        } else {
            XCTFail("expected .downloading")
        }
    }

    func test_is_ready_reflects_resident() {
        let store = ModelStatusStore()
        XCTAssertFalse(store.isReady(.asrWhisperLargeV3Turbo))
        store.set(.resident, for: .asrWhisperLargeV3Turbo)
        XCTAssertTrue(store.isReady(.asrWhisperLargeV3Turbo))
    }

    func test_downloaded_is_not_ready_until_loaded() {
        let store = ModelStatusStore()
        store.set(.downloaded, for: .asrWhisperLargeV3Turbo)
        XCTAssertFalse(store.isReady(.asrWhisperLargeV3Turbo))
    }
}
