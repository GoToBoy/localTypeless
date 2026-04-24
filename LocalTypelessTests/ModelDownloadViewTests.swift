import XCTest
import SwiftUI
import ViewInspector
@testable import LocalTypeless

@MainActor
final class ModelDownloadViewTests: XCTestCase {

    private func makeView(
        kind: ModelKind = .asrWhisperLargeV3Turbo,
        status: ModelStatus = .notDownloaded,
        onStart: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) -> (ModelDownloadView, ModelStatusStore) {
        let store = ModelStatusStore()
        store.set(status, for: kind)
        let view = ModelDownloadView(store: store, kind: kind, onStart: onStart, onCancel: onCancel)
        return (view, store)
    }

    func test_notDownloaded_shows_Download_button_that_fires_onStart() throws {
        var started = false
        let (view, _) = makeView(status: .notDownloaded, onStart: { started = true })
        let button = try view.inspect().find(button: "Download")
        XCTAssertFalse(try button.isDisabled())
        try button.tap()
        XCTAssertTrue(started)
    }

    func test_downloading_shows_disabled_Working_button() throws {
        let (view, _) = makeView(status: .downloading(progress: 0.3))
        let button = try view.inspect().find(button: "Working…")
        XCTAssertTrue(try button.isDisabled())
    }

    func test_downloaded_shows_Load_button() throws {
        let (view, _) = makeView(status: .downloaded)
        XCTAssertNoThrow(try view.inspect().find(button: "Load"))
    }

    func test_resident_shows_Done_button_that_fires_onCancel() throws {
        var cancelled = false
        let (view, _) = makeView(status: .resident, onCancel: { cancelled = true })
        try view.inspect().find(button: "Done").tap()
        XCTAssertTrue(cancelled)
    }

    func test_failed_shows_error_label_and_retry_Download() throws {
        let (view, _) = makeView(status: .failed(message: "boom"))
        XCTAssertNoThrow(try view.inspect().find(text: "boom"))
        XCTAssertNoThrow(try view.inspect().find(button: "Download"))
    }

    func test_title_reflects_asr_kind() throws {
        let (view, _) = makeView(kind: .asrWhisperLargeV3Turbo)
        XCTAssertNoThrow(try view.inspect().find(text: "Download speech model"))
    }

    func test_title_reflects_polish_kind() throws {
        let (view, _) = makeView(kind: .polishQwen25_3bInstruct4bit)
        XCTAssertNoThrow(try view.inspect().find(text: "Download polish model"))
    }
}
