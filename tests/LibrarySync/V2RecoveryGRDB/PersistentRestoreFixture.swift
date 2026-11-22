import Foundation
import GRDB

/// End-to-end dry installation simulation with REAL disk-backed SQLite files.
/// This is a TEST-ONLY isolated temporary directory, never app user storage.
/// It exercises the very same production migrations, preflight and restore SQL.
extension RecoveryFixture {
    static func checkFreshPersistentCombinedRestore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trop-recovery-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        func open(_ name: String) throws -> DatabaseQueue {
            try DatabaseQueue(path: root.appendingPathComponent(name).path)
        }

        func initialize(_ queue: DatabaseQueue) throws {
            var migrator = DatabaseMigrator()
            TropDatabaseMigrationSequence.register(&migrator)
            try migrator.migrate(queue)
        }

        func id(_ i: Int) -> String {
            "b0000000-0000-4000-8000-" + String(format: "%012x", i)
        }

        // Synthetic fixture matches the observed on-device metadata counts:
        // 24 independent V2 recordings, 4 playlists, 10 occurrences.
        // It also includes subsecond Date and repeated playlist recordings.
        let timestamp = Date(timeIntervalSince1970: 1_796_000_123.123456)
        let source = try open("source.sqlite")
        try initialize(source)
        try source.write { db in
            for i in 1...24 {
                try db.execute(sql: """
                    INSERT INTO trop_v2_item
                        (id, kind, title, artist_or_author, duration_seconds,
                         saved_at, liked_at, created_at, modified_at)
                    VALUES (?, 'recording', ?, 'Test Artist', 205, ?, ?, ?, ?)
                    """, arguments: [
                        id(i), "Recovery Track \(i)", timestamp,
                        i <= 12 ? timestamp : nil, timestamp, timestamp
                    ])
            }
            for i in 1...4 {
                try db.execute(sql: """
                    INSERT INTO trop_v2_item
                        (id, kind, title, saved_at, created_at, modified_at)
                    VALUES (?, 'playlist', ?, ?, ?, ?)
                    """, arguments: [
                        id(100 + i), "Recovery Playlist \(i)",
                        timestamp, timestamp, timestamp
                    ])
            }
            for index in 0..<10 {
                let playlist = id(101 + (index % 4))
                // Duplicate recordings intentionally, each with its own UUID.
                let recording = id(1 + index % 6)
                try db.execute(sql: """
                    INSERT INTO trop_v2_playlist_entry
                        (id, playlist_id, recording_id, position, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [
                        id(201 + index), playlist, recording, index / 4, timestamp
                    ])
            }
        }
        let original = try source.read {
            try TropLibraryCombinedBackupService.snapshot(in: $0)
        }
        let archive = try TropLibraryCombinedBackupArchive.encode(original)
        let summary = try TropLibraryCombinedBackupService.preview(archive)
        precondition(summary.legacyTracks == 0)
        precondition(summary.v2Recordings == 24)
        precondition(summary.v2Playlists == 4)
        precondition(summary.v2PlaylistEntries == 10)

        // A genuinely fresh DISK database: start eligible, import using
        // production transaction, restart the connection, compare payload.
        let destination = try open("destination.sqlite")
        try initialize(destination)
        try destination.read { db in
            try TropLibraryCombinedRestorePreflight.requireEmpty(db)
        }
        let restoredPreview = try destination.write {
            try TropLibraryCombinedRestoreStore.restoreInTransaction(
                archive, in: $0
            )
        }
        precondition(restoredPreview == summary)
        // Opening a distinct SQLite connection proves on-disk persistence,
        // as opposed to the already-passing in-memory rehearsal alone.
        let reopened = try open("destination.sqlite")
        let recovered = try reopened.read {
            try TropLibraryCombinedBackupService.snapshot(in: $0)
        }
        precondition(
            TropLibraryCombinedRestoreRehearsal.sameArchiveMetadata(
                original.libraryV2.items, recovered.libraryV2.items
            ),
            "Fresh disk restoration changed V2 metadata"
        )
        precondition(
            TropLibraryCombinedRestoreRehearsal.sameArchiveMetadata(
                original.libraryV2.playlistEntries,
                recovered.libraryV2.playlistEntries
            ),
            "Fresh disk restoration changed 10 playlist occurrences"
        )
        precondition(recovered.legacy == original.legacy)
        precondition(recovered.libraryV2.items.count == 28)
        precondition(recovered.libraryV2.playlistEntries.count == 10)

        // Existing destination must not be altered by a second attempt.
        do {
            _ = try reopened.write {
                try TropLibraryCombinedRestoreStore.restoreInTransaction(
                    archive, in: $0
                )
            }
            preconditionFailure("An occupied disk library was overwritten")
        } catch TropLibraryCombinedRestorePreflight.Blocker.occupiedDestination {
            // Correct: user data remains as it was.
        }
        let afterAttempt = try reopened.read {
            try TropLibraryCombinedBackupService.snapshot(in: $0)
        }
        precondition(afterAttempt.libraryV2 == recovered.libraryV2)

        // TOCTOU protection: the UI may see an empty library, but a user
        // inserts a song before confirmation. Final in-transaction check
        // MUST refuse the restore, preserving that newer song.
        let raced = try open("raced.sqlite")
        try initialize(raced)
        try raced.read {
            try TropLibraryCombinedRestorePreflight.requireEmpty($0)
        }
        try raced.write { db in
            try db.execute(sql: """
                INSERT INTO trop_v2_item
                    (id, kind, title, saved_at, created_at, modified_at)
                VALUES (?, 'recording', 'Do Not Lose Me', ?, ?, ?)
                """, arguments: [id(900), timestamp, timestamp, timestamp])
        }
        do {
            _ = try raced.write {
                try TropLibraryCombinedRestoreStore.restoreInTransaction(
                    archive, in: $0
                )
            }
            preconditionFailure("Restore ignored a concurrent new recording")
        } catch TropLibraryCombinedRestorePreflight.Blocker.occupiedDestination {
            // Correct.
        }
        let surviving = try raced.read {
            try String.fetchOne(
                $0, sql: "SELECT title FROM trop_v2_item WHERE id = ?",
                arguments: [id(900)]
            )
        }
        precondition(surviving == "Do Not Lose Me")
        let racedCount = try raced.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM trop_v2_item")
        }
        precondition(racedCount == 1)

        // Corruption and a mid-transaction SQL failure cannot leave a
        // partially restored disk library. The saved source is untouched.
        let rollback = try open("rollback.sqlite")
        try initialize(rollback)
        try rollback.write { db in
            try db.execute(sql: """
                CREATE TRIGGER recovery_fixture_reject_playlist
                BEFORE INSERT ON trop_v2_playlist_entry
                BEGIN SELECT RAISE(ABORT, 'recovery-fixture-rollback'); END
                """)
        }
        do {
            _ = try rollback.write {
                try TropLibraryCombinedRestoreStore.restoreInTransaction(
                    archive, in: $0
                )
            }
            preconditionFailure("Fixture trigger should abort restore")
        } catch {
            // Expected SQLite trigger abort.
        }
        try rollback.read {
            try TropLibraryCombinedRestorePreflight.requireEmpty($0)
        }
        let stillSource = try source.read {
            try TropLibraryCombinedBackupService.snapshot(in: $0)
        }
        precondition(stillSource == original)
        print(
            "Fresh disk-backed recovery passed: 24 songs, 4 playlists, "
                + "10 ordered entries; reopen, occupied/race guards, "
                + "transaction rollback, source preserved"
        )
    }
}
