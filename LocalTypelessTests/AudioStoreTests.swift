import XCTest
@testable import LocalTypeless

final class AudioStoreTests: XCTestCase {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func test_save_writes_wav_file() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = AudioStore(directory: dir)
        let samples: [Float] = Array(repeating: 0.1, count: 16_000)  // 1 second
        let url = try store.save(samples: samples, sampleRate: 16_000)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertGreaterThan((attrs[.size] as? Int) ?? 0, 1000)
    }

    func test_pruneOlderThan_removes_old_files() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = AudioStore(directory: dir)
        let oldFile = dir.appendingPathComponent("old.wav")
        let newFile = dir.appendingPathComponent("new.wav")
        try Data([0]).write(to: oldFile)
        try Data([0]).write(to: newFile)

        // Backdate old file to 10 days ago
        let tenDaysAgo = Date().addingTimeInterval(-10 * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: tenDaysAgo],
            ofItemAtPath: oldFile.path
        )

        try store.pruneOlderThan(days: 7)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path))
    }
}
