import Foundation
import GRDB

/// Isolated substitute exposing the same actor API as production
/// DatabaseService; the actual V2RecoveryStore source is compiled unchanged.
actor DatabaseService {
    nonisolated static let shared = DatabaseService()
    nonisolated let usesPersistentStore = true
    let dbPool: DatabasePool
    private(set) var readCount = 0

    private init() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("trop-v2-grdb-fixture-\(UUID().uuidString).sqlite")
        guard let pool = try? DatabasePool(path: file.path) else {
            fatalError("Unable to set up isolated GRDB recovery fixture")
        }
        dbPool = pool
    }

    func read<T: Sendable>(
        _ block: @escaping @Sendable (Database) throws -> T
    ) async throws -> T {
        readCount += 1
        return try await dbPool.read { db in try block(db) }
    }

    func write(
        _ block: @escaping @Sendable (Database) throws -> Void
    ) async throws {
        try await dbPool.write { db in try block(db) }
    }
}

@main
enum RecoveryFixture {
    static let now = Date(timeIntervalSince1970: 1_799_000_000)
    static let recording = "a0000000-0000-4000-8000-000000000001"
    static let playlist = "a0000000-0000-4000-8000-000000000002"
    static let episode = "a0000000-0000-4000-8000-000000000003"
    static let entry1 = "a0000000-0000-4000-8000-000000000004"
    static let entry2 = "a0000000-0000-4000-8000-000000000005"
    static let safeAlias = "a0000000-0000-4000-8000-000000000006"
    static let privateAlias = "a0000000-0000-4000-8000-000000000007"
    static let radio = "a0000000-0000-4000-8000-000000000008"
    static let relation = "a0000000-0000-4000-8000-000000000009"

    static let tables = [
        "trop_v2_item",
        "trop_v2_source_alias",
        "trop_v2_playlist_entry",
        "trop_v2_radio_favorite",
        "trop_v2_legacy_import_entry",
        "trop_v2_legacy_relation"
    ]

    static func clearV2() async throws {
        try await DatabaseService.shared.write { db in
            // Fixture-only deletion, NEVER called in production recovery.
            for table in [
                "trop_v2_legacy_import_entry",
                "trop_v2_playlist_entry",
                "trop_v2_source_alias",
                "trop_v2_legacy_relation",
                "trop_v2_radio_favorite",
                "trop_v2_item"
            ] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    static func assertEmptyV2() async throws {
        try await DatabaseService.shared.read { db in
            for table in tables {
                let count = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM \(table)"
                )
                precondition(count == 0, "Unexpected rows in \(table)")
            }
        }
    }

    static func createSchema(from path: String) async throws {
        let ddlText = try String(contentsOfFile: path, encoding: .utf8)
        let statements = ddlText.components(separatedBy: "\n--V2DDL--\n")
        precondition(statements.count == 10, "Must use actual v10-v12 schema")
        try await DatabaseService.shared.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // Legacy tables contain only the production columns used by
            // the allowlisted metadata SELECTs; no credentials or paths.
            try db.execute(sql: """
                CREATE TABLE song (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL, artist_name TEXT,
                    album_name TEXT, duration INTEGER NOT NULL,
                    liked INTEGER NOT NULL, in_library DATETIME,
                    is_episode INTEGER NOT NULL, create_date DATETIME NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE playlist (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, browse_id TEXT,
                    bookmarked_at DATETIME, is_editable INTEGER NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE playlist_song_map (
                    id INTEGER PRIMARY KEY, playlist_id TEXT,
                    song_id TEXT, position INTEGER
                )
                """)
            try db.execute(sql: """
                CREATE TABLE album (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL,
                    bookmarked_at DATETIME
                )
                """)
            try db.execute(sql: """
                CREATE TABLE artist (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL,
                    bookmarked_at DATETIME
                )
                """)
            try db.execute(sql: """
                CREATE TABLE podcast (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL,
                    subscribed_at DATETIME
                )
                """)
            try db.execute(sql: """
                CREATE TABLE episode (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL,
                    podcast_id TEXT, duration INTEGER NOT NULL,
                    is_played INTEGER NOT NULL, saved_at DATETIME
                )
                """)
            try db.execute(
                sql: """
                    INSERT INTO song
                        (id, title, artist_name, duration, liked,
                         is_episode, create_date)
                    VALUES ('legacy-keep', 'Legacy song preserved',
                            'Legacy Artist', 180, 1, 0, ?)
                    """,
                arguments: [now]
            )
            try db.execute(
                sql: """
                    INSERT INTO playlist
                        (id, name, browse_id, bookmarked_at, is_editable)
                    VALUES ('old-playlist', 'Legacy Playlist', NULL, ?, 1)
                    """,
                arguments: [now]
            )
            for statement in statements {
                try db.execute(sql: statement)
            }
        }
    }

    static func createSource() async throws {
        try await DatabaseService.shared.write { db in
            try db.execute(sql: """
                INSERT INTO playlist_song_map
                    (id, playlist_id, song_id, position)
                VALUES (11, 'old-playlist', 'legacy-keep', 0)
                """)
            for (id, kind, title, author) in [
                (recording, "recording", "Una Canción", "Artista"),
                (playlist, "playlist", "Mi Playlist", ""),
                (episode, "episode", "Podcast Episode", "Host")
            ] {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_item
                            (id, kind, title, artist_or_author, duration_seconds,
                             saved_at, liked_at, created_at, modified_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        id, kind, title, author,
                        kind == "recording" ? 198 : 0,
                        now, kind == "recording" ? now : nil, now, now
                    ]
                )
            }

            for (id, provider, externalID) in [
                (safeAlias, "youtube", "video-id-123"),
                (privateAlias, "addon", "addon:encoded-private-manifest")
            ] {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_source_alias
                            (id, item_id, kind, provider, source_scope, external_id)
                        VALUES (?, ?, 'recording', ?, 'global', ?)
                        """,
                    arguments: [id, recording, provider, externalID]
                )
            }
            for (id, order) in [(entry1, 0), (entry2, 1)] {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_playlist_entry
                            (id, playlist_id, recording_id, position, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [id, playlist, recording, order, now]
                )
            }
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_radio_favorite
                        (id, station_uuid, name, subtitle, added_at)
                    VALUES (?, '9617ba77-0601-11e8-ae97-52543be04c81',
                            'Latina Salsa', '', ?)
                    """,
                arguments: [radio, now]
            )
            for (key, id) in [(Int64(11), entry1), (Int64(12), entry2)] {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_legacy_import_entry
                            (legacy_membership_id, entry_id, imported_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [key, id, now]
                )
            }
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_legacy_relation
                        (id, owner_item_id, link_kind, external_id, created_at)
                    VALUES (?, ?, 'episode_podcast', 'podcast-from-youtube', ?)
                    """,
                arguments: [relation, episode, now]
            )
        }
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected extracted v10-v12 SQL fixture path")
        }
        try await createSchema(from: CommandLine.arguments[1])
        try await createSource()

        // Both independent metadata models are obtained from precisely one
        // production GRDB read closure; confirm no extra read slips in.
        let readsBefore = await DatabaseService.shared.readCount
        let combinedArchive = try await TropLibraryCombinedBackupService.export()
        let readsAfter = await DatabaseService.shared.readCount
        precondition(readsAfter == readsBefore + 1, "Combined export must use one read")
        let combined = try TropLibraryCombinedBackupArchive.decode(combinedArchive)
        precondition(combined.library.legacy.tracks.count == 1)
        precondition(combined.library.legacy.tracks[0].title == "Legacy song preserved")
        precondition(combined.library.legacy.playlists.count == 1)
        precondition(combined.library.libraryV2.items.count == 3)
        precondition(combined.library.libraryV2.playlistEntries.count == 2)
        precondition(combined.library.libraryV2.omittedPrivateAliases == 1)
        let combinedSummary = try TropLibraryCombinedBackupService.preview(combinedArchive)
        precondition(combinedSummary.legacyTracks == 1 && combinedSummary.v2Playlists == 1)
        precondition(combinedSummary.legacyLedgerEntriesNeedingOrigin == 2)
        precondition(combinedSummary.sourceMemberships == 1)
        precondition(combinedSummary.ledgerEntriesWithMissingMembership == 1)
        precondition(combined.library.legacyMemberships.count == 1)
        precondition(combined.library.legacyMemberships[0].sourceRowID == 11)
        precondition(combined.library.legacyMemberships[0].songID == "legacy-keep")
        precondition(!String(decoding: combinedArchive, as: UTF8.self)
            .contains("encoded-private-manifest"))

        // This is the actual export/snapshot implementation, not a copy.
        let original = try await TropLibraryV2RecoveryStore.snapshot()
        precondition(original.omittedPrivateAliases == 1)
        precondition(original.aliases.count == 1)
        precondition(original.aliases[0].externalID == "video-id-123")
        precondition(original.playlistEntries.map(\.position) == [0, 1])
        let archive = try await TropLibraryV2RecoveryStore.export()
        precondition(!String(decoding: archive, as: UTF8.self).contains("encoded-private-manifest"))
        let detail = try TropLibraryV2RecoveryStore.preview(archive)
        precondition(detail.playlists == 1 && detail.entries == 2)
        precondition(detail.omittedPrivateAliases == 1)

        try await clearV2()
        try await assertEmptyV2()

        // Inject a real SQL failure only after item/alias/entry insertion.
        // The production GRDB transaction must roll all tables back.
        try await DatabaseService.shared.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fixture_fail_radio
                BEFORE INSERT ON trop_v2_radio_favorite
                BEGIN SELECT RAISE(ABORT, 'fixture-injected'); END
                """)
        }
        do {
            _ = try await TropLibraryV2RecoveryStore.restoreIntoEmptyLibrary(archive)
            preconditionFailure("Expected real GRDB failure")
        } catch {
            // Expected: injected SQLite transaction failure.
        }
        try await assertEmptyV2()
        try await DatabaseService.shared.write { db in
            try db.execute(sql: "DROP TRIGGER fixture_fail_radio")
        }

        // Perform an actual GRDB restore; preserve duplicate positions and
        // original IDs. Private add-on credentials were never serialized.
        let restoredSummary = try await TropLibraryV2RecoveryStore.restoreIntoEmptyLibrary(archive)
        precondition(restoredSummary == detail)
        let restored = try await TropLibraryV2RecoveryStore.snapshot()
        precondition(restored.items == original.items)
        precondition(restored.aliases == original.aliases)
        precondition(restored.playlistEntries == original.playlistEntries)
        precondition(restored.radioFavorites == original.radioFavorites)
        precondition(restored.importLedger == original.importLedger)
        precondition(restored.legacyRelations == original.legacyRelations)
        precondition(restored.omittedPrivateAliases == 0)

        do {
            _ = try await TropLibraryV2RecoveryStore.restoreIntoEmptyLibrary(archive)
            preconditionFailure("Must refuse overwrite of existing V2 data")
        } catch TropLibraryV2RecoveryError.existingLibrary {
            // Correct: no overwrite.
        }
        let stillThere = try await TropLibraryV2RecoveryStore.snapshot()
        precondition(stillThere.items == restored.items)

        // Deleting an entry must turn its ledger pointer into a tombstone.
        try await DatabaseService.shared.write { db in
            try db.execute(
                sql: "DELETE FROM trop_v2_playlist_entry WHERE id = ?",
                arguments: [entry1]
            )
            let pointer = try String.fetchOne(
                db,
                sql: """
                    SELECT entry_id FROM trop_v2_legacy_import_entry
                    WHERE legacy_membership_id = 11
                    """
            )
            precondition(pointer == nil)
        }

        // A foreign legacy database makes integer row IDs ambiguous.
        try await clearV2()
        try await DatabaseService.shared.write { db in
            try db.execute(sql: """
                INSERT INTO playlist_song_map
                    (id, playlist_id, song_id, position)
                VALUES (11, 'different-playlist', 'different-song', 0)
                """)
        }
        do {
            _ = try await TropLibraryV2RecoveryStore.restoreIntoEmptyLibrary(archive)
            preconditionFailure("Must refuse ambiguous legacy provenance")
        } catch TropLibraryV2RecoveryError.legacySourceConflict {
            // Correct.
        }
        try await assertEmptyV2()
        try await DatabaseService.shared.read { db in
            let title = try String.fetchOne(
                db, sql: "SELECT title FROM song WHERE id = 'legacy-keep'"
            )
            precondition(title == "Legacy song preserved")
        }
        print("Real GRDB V2 export/restore, rollback, private alias redaction and collision checks passed")
    }
}
