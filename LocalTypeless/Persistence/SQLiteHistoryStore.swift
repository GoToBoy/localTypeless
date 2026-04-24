import Foundation
import GRDB

final class SQLiteHistoryStore: HistoryStore {

    private let dbQueue: DatabaseQueue

    init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.dbQueue = try DatabaseQueue(path: path.path)
        try migrate()
    }

    private func migrate() throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "dictation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("started_at", .datetime).notNull()
                t.column("duration_ms", .integer).notNull()
                t.column("raw_transcript", .text).notNull()
                t.column("polished_text", .text).notNull()
                t.column("language", .text).notNull()
                t.column("target_app_bundle_id", .text)
                t.column("target_app_name", .text)
            }
            try db.create(index: "idx_dictation_started_at",
                          on: "dictation", columns: ["started_at"])
        }
        try m.migrate(dbQueue)
    }

    func insert(_ entry: DictationEntry) throws -> Int64 {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO dictation
                    (started_at, duration_ms, raw_transcript, polished_text,
                     language, target_app_bundle_id, target_app_name)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                entry.startedAt, entry.durationMs, entry.rawTranscript,
                entry.polishedText, entry.language,
                entry.targetAppBundleId, entry.targetAppName
            ])
            return db.lastInsertedRowID
        }
    }

    func all() throws -> [DictationEntry] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM dictation ORDER BY started_at DESC
            """).map(Self.decode)
        }
    }

    func search(query: String) throws -> [DictationEntry] {
        try dbQueue.read { db in
            let like = "%\(query)%"
            return try Row.fetchAll(db, sql: """
                SELECT * FROM dictation
                WHERE raw_transcript LIKE ? OR polished_text LIKE ?
                ORDER BY started_at DESC
            """, arguments: [like, like]).map(Self.decode)
        }
    }

    func delete(id: Int64) throws {
        _ = try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM dictation WHERE id = ?", arguments: [id])
        }
    }

    private static func decode(_ row: Row) -> DictationEntry {
        DictationEntry(
            id: row["id"],
            startedAt: row["started_at"],
            durationMs: row["duration_ms"],
            rawTranscript: row["raw_transcript"],
            polishedText: row["polished_text"],
            language: row["language"],
            targetAppBundleId: row["target_app_bundle_id"],
            targetAppName: row["target_app_name"]
        )
    }
}
