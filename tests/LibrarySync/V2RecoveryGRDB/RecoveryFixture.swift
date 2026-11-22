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
        precondition(statements.count == 12, "Must use actual v10-v13 schema")
        try await DatabaseService.shared.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // Legacy tables contain only the production columns used by
            // the allowlisted metadata SELECTs; no credentials or paths.
            try db.execute(sql: """
                CREATE TABLE song (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL, artist_name TEXT,
                    album_name TEXT, duration INTEGER NOT NULL,
                    liked INTEGER NOT NULL, in_library DATETIME,
                    is_episode INTEGER NOT NULL, create_date DATETIME NOT NULL,
                    modify_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
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
                    playlist_id TEXT, bookmarked_at DATETIME
                )
                """)
            try db.execute(sql: """
                CREATE TABLE artist (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL,
                    channel_id TEXT, bookmarked_at DATETIME,
                    is_podcast_channel INTEGER NOT NULL DEFAULT 0
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
                    podcast_name TEXT, is_played INTEGER NOT NULL,
                    saved_at DATETIME
                )
                """)
            try db.execute(sql: """
                CREATE TABLE podcast_episode_map (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    podcast_id TEXT NOT NULL, episode_id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    UNIQUE (podcast_id, episode_id)
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
            // v13's migration seeds a persistent per-installation UUID.
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_library_origin (singleton, origin_scope)
                    VALUES (1, ?)
                    """,
                arguments: ["a0000000-0000-4000-8000-000000000099"]
            )
        }
    }

    static func createSource() async throws {
        try await DatabaseService.shared.write { db in
            try db.execute(sql: """
                INSERT INTO playlist_song_map
                    (id, playlist_id, song_id, position)
                VALUES (11, 'old-playlist', 'legacy-keep', 0)
                """)
            // Saved albums/artists retain public source IDs even when their
            // remote catalogue is not present as a local playlist.
            try db.execute(
                sql: """
                    INSERT INTO album (id, title, playlist_id, bookmarked_at)
                    VALUES ('legacy-album', 'Saved album', 'OL-album-source', ?)
                    """,
                arguments: [now]
            )
            try db.execute(
                sql: """
                    INSERT INTO artist
                        (id, name, channel_id, bookmarked_at, is_podcast_channel)
                    VALUES ('legacy-artist', 'Saved artist', 'UC-channel-source', ?, 1)
                    """,
                arguments: [now]
            )
            // One saved/subscribed pair and one unflagged pair. Neither
            // legacy metadata state nor their ordering may be lost.
            try db.execute(
                sql: """
                    INSERT INTO podcast (id, name, subscribed_at)
                    VALUES ('saved-podcast', 'Subscribed Show', ?),
                           ('linked-podcast', 'Unsubscribed Show', NULL)
                    """,
                arguments: [now]
            )
            try db.execute(
                sql: """
                    INSERT INTO episode
                        (id, title, podcast_id, duration,
                         podcast_name, is_played, saved_at)
                    VALUES ('saved-episode', 'Saved Episode',
                            'saved-podcast', 180, 'Subscribed Show', 1, ?),
                           ('linked-episode', 'Unsaved Episode',
                            'linked-podcast', 240, 'Unsubscribed Show', 0, NULL)
                    """,
                arguments: [now]
            )
            try db.execute(sql: """
                INSERT INTO podcast_episode_map (podcast_id, episode_id, position)
                VALUES ('saved-podcast', 'saved-episode', 1),
                       ('linked-podcast', 'linked-episode', 7)
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

    /// Real SQLite AUTOINCREMENT assigns a different destination row ID.
    /// The planner maps that observed ID to the source membership tuple.
    /// An orphan ledger entry aborts a transaction without partial writes.
    static func checkCombinedRemapping(
        originalArchive: Data,
        original: TropLibraryCombinedBackupSnapshot
    ) throws {
        let sourceRow = try {
            guard let row = original.legacyMemberships.first else {
                throw TropLibraryCombinedRestorePlanner.Blocker.incompleteMembershipMapping
            }
            return row
        }()
        let destination = try DatabaseQueue()
        let actual = try destination.write { db -> TropLibraryCombinedRestorePlanner.DestinationMembership in
            try db.execute(sql: """
                CREATE TABLE restored_membership (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    playlist_id TEXT NOT NULL,
                    song_id TEXT NOT NULL,
                    position INTEGER NOT NULL
                )
                """)
            // Simulate a consumed SQLite row ID with an empty destination.
            try db.execute(
                sql: """
                    INSERT INTO restored_membership
                        (id, playlist_id, song_id, position)
                    VALUES (800, 'temp', 'temp', 0)
                    """
            )
            try db.execute(sql: "DELETE FROM restored_membership")
            try db.execute(
                sql: """
                    INSERT INTO restored_membership
                        (playlist_id, song_id, position)
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    sourceRow.playlistID, sourceRow.songID, sourceRow.position
                ]
            )
            let newID = db.lastInsertedRowID
            guard let row = try Row.fetchOne(
                db, sql: """
                    SELECT playlist_id, song_id, position
                    FROM restored_membership WHERE id = ?
                    """,
                arguments: [newID]
            ) else {
                throw TropLibraryCombinedRestorePlanner.Blocker.incompleteMembershipMapping
            }
            return .init(
                sourceRowID: sourceRow.sourceRowID,
                assignedRowID: newID,
                playlistID: row["playlist_id"],
                songID: row["song_id"],
                position: row["position"]
            )
        }
        precondition(actual.assignedRowID != sourceRow.sourceRowID)

        // A complete live-row map is safe to remap; archived imported-entry
        // tombstones still cannot be resolved without stable origin IDs.
        let v2 = original.libraryV2
        let safeSource = TropLibraryCombinedBackupSnapshot(
            legacy: original.legacy,
            libraryV2: .init(
                items: v2.items, aliases: v2.aliases,
                playlistEntries: v2.playlistEntries,
                radioFavorites: v2.radioFavorites,
                importLedger: v2.importLedger.filter {
                    $0.legacyMembershipID == sourceRow.sourceRowID
                },
                legacyRelations: v2.legacyRelations,
                omittedPrivateAliases: v2.omittedPrivateAliases
            ),
            legacyMemberships: original.legacyMemberships,
            originScope: original.originScope,
            foreignTombstones: original.foreignTombstones
        )
        let validArchive = try TropLibraryCombinedBackupArchive.encode(safeSource)
        let plan = try TropLibraryCombinedRestorePlanner.prepare(
            archive: validArchive, insertedMemberships: [actual]
        )
        precondition(
            plan.sourceToDestinationID[sourceRow.sourceRowID]
                == actual.assignedRowID
        )
        precondition(
            plan.remappedImportLedger.first?.legacyMembershipID
                == actual.assignedRowID
        )

        // Orphan history is isolated by origin, never assigned local IDs.
        let quarantined = try TropLibraryCombinedRestorePlanner.prepare(
            archive: originalArchive, insertedMemberships: [actual]
        )
        precondition(quarantined.foreignTombstones.count == 1)
        precondition(quarantined.foreignTombstones[0].sourceMembershipID == 12)
        precondition(quarantined.foreignTombstones[0].originScope == original.originScope)

        let rollback = try DatabaseQueue()
        try rollback.write { db in
            try db.execute(sql: """
                CREATE TABLE restored_membership (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    playlist_id TEXT NOT NULL,
                    song_id TEXT NOT NULL,
                    position INTEGER NOT NULL
                )
                """)
        }
        do {
            try rollback.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO restored_membership
                            (playlist_id, song_id, position)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [
                        sourceRow.playlistID, sourceRow.songID, sourceRow.position
                    ]
                )
                let assigned = TropLibraryCombinedRestorePlanner.DestinationMembership(
                    sourceRowID: sourceRow.sourceRowID,
                    assignedRowID: db.lastInsertedRowID,
                    playlistID: sourceRow.playlistID,
                    songID: sourceRow.songID,
                    position: sourceRow.position
                )
                _ = try TropLibraryCombinedRestorePlanner.prepare(
                    archive: originalArchive, insertedMemberships: [assigned]
                )
                throw TropLibraryCombinedRestorePlanner.Blocker.wrongMembershipIdentity
            }
            preconditionFailure("Injected transaction must roll back")
        } catch TropLibraryCombinedRestorePlanner.Blocker.wrongMembershipIdentity {}
        let remaining = try rollback.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM restored_membership")
        }
        precondition(remaining == 0, "Failed remap must rollback SQLite writes")
    }

    /// Preflight is read-only and must reject preexisting user data and
    /// partially migrated schemas without touching any source rows.
    static func checkCombinedRestorePreflight() throws {
        let missing = try DatabaseQueue()
        do {
            try missing.read { db in
                try TropLibraryCombinedRestorePreflight.requireEmpty(db)
            }
            preconditionFailure("Missing schema must be rejected")
        } catch TropLibraryCombinedRestorePreflight.Blocker.missingSchema(let name) {
            precondition(name == "song")
        }

        let clean = try DatabaseQueue()
        try clean.write { db in
            for table in TropLibraryCombinedRestorePreflight.requiredTables {
                try db.execute(sql: "CREATE TABLE \(table) (id INTEGER PRIMARY KEY)")
            }
        }
        try clean.read { db in
            try TropLibraryCombinedRestorePreflight.requireEmpty(db)
        }

        // A downloaded audio record counts as nonempty even when the
        // visible music/playlist tables are all empty.
        try clean.write { db in
            try db.execute(
                sql: "CREATE TABLE downloaded_track (id INTEGER PRIMARY KEY)"
            )
            try db.execute(sql: "INSERT INTO downloaded_track (id) VALUES (7)")
        }
        do {
            try clean.read { db in
                try TropLibraryCombinedRestorePreflight.requireEmpty(db)
            }
            preconditionFailure("Downloaded data must block full restoration")
        } catch TropLibraryCombinedRestorePreflight.Blocker.occupiedDestination(let name) {
            precondition(name == "downloaded_track")
        }

        try clean.write { db in
            try db.execute(sql: "DELETE FROM downloaded_track WHERE id = 7")
            try db.execute(sql: "INSERT INTO song (id) VALUES (11)")
        }
        do {
            try clean.read { db in
                try TropLibraryCombinedRestorePreflight.requireEmpty(db)
            }
            preconditionFailure("Legacy music must block overwrite")
        } catch TropLibraryCombinedRestorePreflight.Blocker.occupiedDestination(let name) {
            precondition(name == "song")
        }
        let original = try clean.read { db in
            try Int.fetchOne(db, sql: "SELECT id FROM song LIMIT 1")
        }
        precondition(original == 11, "Preflight must never mutate legacy data")
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected extracted v10-v12 SQL fixture path")
        }
        try checkCombinedRestorePreflight()
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
        precondition(combined.library.legacy.albums.count == 1)
        precondition(combined.library.legacy.artists.count == 1)
        precondition(combined.library.legacyAlbumSources.count == 1)
        precondition(combined.library.legacyAlbumSources[0].sourcePlaylistID == "OL-album-source")
        precondition(combined.library.legacyArtistSources.count == 1)
        precondition(combined.library.legacyArtistSources[0].sourceChannelID == "UC-channel-source")
        precondition(combined.library.podcastArtists.count == 1)
        precondition(combined.library.podcastArtists[0].artistID == "legacy-artist")
        precondition(combined.library.episodePodcastNames.count == 2)
        precondition(combined.library.legacy.podcasts.count == 1)
        precondition(combined.library.legacy.episodes.count == 1)
        precondition(combined.library.relatedPodcasts.count == 1)
        precondition(combined.library.relatedEpisodes.count == 1)
        precondition(combined.library.podcastEpisodeMemberships.count == 2)
        precondition(combined.library.libraryV2.radioFavorites.count == 1)
        precondition(combined.library.libraryV2.radioFavorites[0].name == "Latina Salsa")
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
        try checkCombinedRemapping(
            originalArchive: combinedArchive, original: combined.library
        )

        // The subsequent V2-only restore fixture starts with no legacy
        // memberships, as required by that older restore's collision guard.
        // This is fixture-only deletion, never production restore behavior.
        try await DatabaseService.shared.write { db in
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE id = 11")
        }

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

        // Internal combined restore against a disposable GRDB fixture.
        // A failed tombstone insert must roll back legacy and V2 together.
        try await DatabaseService.shared.write { db in
            for table in [
                "trop_v2_legacy_import_entry", "trop_v2_playlist_entry",
                "trop_v2_source_alias", "trop_v2_legacy_relation",
                "trop_v2_radio_favorite", "trop_v2_item",
                "playlist_song_map", "song", "album", "artist",
                "playlist", "podcast", "episode", "podcast_episode_map"
            ] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
        // The destination has its OWN installation origin, not the source's.
        try await DatabaseService.shared.write { db in
            try db.execute(
                sql: "UPDATE trop_v2_library_origin SET origin_scope = ? WHERE singleton = 1",
                arguments: ["b0000000-0000-4000-8000-000000000099"]
            )
            try db.execute(sql: """
                CREATE TRIGGER fixture_fail_combined_tombstone
                BEFORE INSERT ON trop_v2_foreign_import_tombstone
                BEGIN SELECT RAISE(ABORT, 'foreign-tombstone-injected'); END
                """)
        }
        do {
            _ = try await TropLibraryCombinedRestoreStore.restoreIntoEmptyLibrary(
                combinedArchive
            )
            preconditionFailure("Failed tombstone insert must abort restore")
        } catch {
            // Fixture-only injected SQLite error, check full rollback below.
        }
        try await DatabaseService.shared.write { db in
            try db.execute(sql: "DROP TRIGGER fixture_fail_combined_tombstone")
        }
        try await DatabaseService.shared.read { db in
            for table in ["song", "playlist", "playlist_song_map", "trop_v2_item"] {
                let count = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM \(table)"
                ) ?? -1
                precondition(count == 0, "Orphan should rollback every table")
            }
        }

        // Synthetic fixture: an archive with only live import membership IDs,
        // used for a late V2 SQL failure test. Orphans remain preserved
        // separately in the original combined archive.
        let sourceV2 = combined.library.libraryV2
        let safeSource = TropLibraryCombinedBackupSnapshot(
            legacy: combined.library.legacy,
            libraryV2: .init(
                items: sourceV2.items, aliases: sourceV2.aliases,
                playlistEntries: sourceV2.playlistEntries,
                radioFavorites: sourceV2.radioFavorites,
                importLedger: sourceV2.importLedger.filter {
                    $0.legacyMembershipID == 11
                },
                legacyRelations: sourceV2.legacyRelations,
                omittedPrivateAliases: sourceV2.omittedPrivateAliases
            ),
            legacyMemberships: combined.library.legacyMemberships,
            originScope: combined.library.originScope,
            foreignTombstones: combined.library.foreignTombstones
        )
        let safeArchive = try TropLibraryCombinedBackupArchive.encode(safeSource)

        // Force a failure AFTER the legacy rows and V2 items have been
        // inserted, proving rollback from a real SQLite constraint trigger.
        try await DatabaseService.shared.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fixture_fail_combined_radio
                BEFORE INSERT ON trop_v2_radio_favorite
                BEGIN SELECT RAISE(ABORT, 'combined-rollback'); END
                """)
        }
        do {
            _ = try await TropLibraryCombinedRestoreStore.restoreIntoEmptyLibrary(
                safeArchive
            )
            preconditionFailure("Late SQLite failure must rollback combined restore")
        } catch {
            // Trigger failure is expected, but check no transaction survived.
        }
        try await DatabaseService.shared.read { db in
            for table in [
                "song", "playlist", "playlist_song_map",
                "trop_v2_item", "trop_v2_source_alias",
                "trop_v2_playlist_entry"
            ] {
                let count = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM \(table)"
                ) ?? -1
                precondition(count == 0, "Late failure must rollback legacy and V2")
            }
        }
        try await DatabaseService.shared.write { db in
            try db.execute(sql: "DROP TRIGGER fixture_fail_combined_radio")
        }

        let summary = try await TropLibraryCombinedRestoreStore.restoreIntoEmptyLibrary(
            combinedArchive
        )
        precondition(summary.legacyTracks == 1 && summary.v2Playlists == 1)
        let restoredCombined = try await TropLibraryCombinedBackupService.snapshot()
        precondition(restoredCombined.legacy.tracks.count == 1)
        precondition(restoredCombined.legacy.playlists.count == 1)
        precondition(restoredCombined.legacy.albums == combined.library.legacy.albums)
        precondition(restoredCombined.legacy.artists == combined.library.legacy.artists)
        precondition(
            restoredCombined.legacyAlbumSources == combined.library.legacyAlbumSources
        )
        precondition(
            restoredCombined.legacyArtistSources == combined.library.legacyArtistSources
        )
        precondition(restoredCombined.podcastArtists == combined.library.podcastArtists)
        precondition(
            restoredCombined.episodePodcastNames == combined.library.episodePodcastNames
        )
        precondition(restoredCombined.legacy.podcasts == combined.library.legacy.podcasts)
        precondition(restoredCombined.legacy.episodes == combined.library.legacy.episodes)
        precondition(restoredCombined.relatedPodcasts == combined.library.relatedPodcasts)
        precondition(restoredCombined.relatedEpisodes == combined.library.relatedEpisodes)
        precondition(
            restoredCombined.podcastEpisodeMemberships
                == combined.library.podcastEpisodeMemberships
        )
        precondition(
            restoredCombined.libraryV2.radioFavorites
                == combined.library.libraryV2.radioFavorites
        )
        precondition(restoredCombined.libraryV2.radioFavorites.count == 1)
        precondition(restoredCombined.legacyMemberships.count == 1)
        precondition(restoredCombined.libraryV2.items.count == 3)
        precondition(restoredCombined.libraryV2.playlistEntries.count == 2)
        precondition(restoredCombined.libraryV2.importLedger.count == 1)
        precondition(restoredCombined.foreignTombstones.count == 1)
        precondition(restoredCombined.foreignTombstones[0].sourceMembershipID == 12)
        precondition(restoredCombined.foreignTombstones[0].originScope == combined.library.originScope)
        precondition(restoredCombined.originScope != combined.library.originScope)
        let reexported = try await TropLibraryCombinedBackupService.export()
        let redecoded = try TropLibraryCombinedBackupArchive.decode(reexported)
        precondition(redecoded.library.foreignTombstones == restoredCombined.foreignTombstones)
        precondition(redecoded.library.legacyAlbumSources == combined.library.legacyAlbumSources)
        precondition(redecoded.library.legacyArtistSources == combined.library.legacyArtistSources)
        precondition(redecoded.library.podcastArtists == combined.library.podcastArtists)
        precondition(
            redecoded.library.episodePodcastNames == combined.library.episodePodcastNames
        )
        precondition(
            redecoded.library.podcastEpisodeMemberships
                == combined.library.podcastEpisodeMemberships
        )
        precondition(redecoded.library.libraryV2.radioFavorites == combined.library.libraryV2.radioFavorites)
        precondition(!String(decoding: reexported, as: UTF8.self).contains("stream_url"))
        precondition(
            restoredCombined.libraryV2.importLedger[0].legacyMembershipID
                == restoredCombined.legacyMemberships[0].sourceRowID
        )

        // Repeated restores must fail closed without changing existing rows.
        do {
            _ = try await TropLibraryCombinedRestoreStore.restoreIntoEmptyLibrary(
                combinedArchive
            )
            preconditionFailure("Combined restore must not overwrite user data")
        } catch TropLibraryCombinedRestorePreflight.Blocker.occupiedDestination {}
        let afterRepeat = try await TropLibraryCombinedBackupService.snapshot()
        precondition(afterRepeat.legacy.tracks == restoredCombined.legacy.tracks)
        precondition(afterRepeat.libraryV2.items == restoredCombined.libraryV2.items)

        // No-YouTube / no-provider restore: a metadata archive with ZERO
        // provider aliases or legacy provider links must still carry all
        // Trop-owned playlists, podcast relationships and radio favorites.
        // This proves database portability, NOT live stream playability.
        let sourceWithNoProvider = TropLibraryCombinedBackupSnapshot(
            legacy: combined.library.legacy,
            libraryV2: .init(
                items: sourceV2.items,
                aliases: [],
                playlistEntries: sourceV2.playlistEntries,
                radioFavorites: sourceV2.radioFavorites,
                importLedger: sourceV2.importLedger,
                legacyRelations: [],
                omittedPrivateAliases: 0
            ),
            legacyMemberships: combined.library.legacyMemberships,
            originScope: combined.library.originScope,
            foreignTombstones: combined.library.foreignTombstones,
            relatedPodcasts: combined.library.relatedPodcasts,
            relatedEpisodes: combined.library.relatedEpisodes,
            podcastEpisodeMemberships: combined.library.podcastEpisodeMemberships,
            podcastArtists: combined.library.podcastArtists,
            episodePodcastNames: combined.library.episodePodcastNames
        )
        let noProviderArchive = try TropLibraryCombinedBackupArchive.encode(
            sourceWithNoProvider
        )
        let noProviderJSON = String(decoding: noProviderArchive, as: UTF8.self)
        precondition(!noProviderJSON.contains("youtube"))
        precondition(!noProviderJSON.contains("addon:"))
        precondition(!noProviderJSON.contains("stream_url"))

        // Fixture-only reset. Production restore has NO reset/delete path.
        try await DatabaseService.shared.write { db in
            for table in [
                "trop_v2_legacy_import_entry", "trop_v2_foreign_import_tombstone",
                "trop_v2_playlist_entry", "trop_v2_source_alias",
                "trop_v2_legacy_relation", "trop_v2_radio_favorite",
                "trop_v2_item", "playlist_song_map", "podcast_episode_map",
                "song", "album", "artist", "playlist", "podcast", "episode"
            ] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
        _ = try await TropLibraryCombinedRestoreStore.restoreIntoEmptyLibrary(
            noProviderArchive
        )
        let restoredWithoutProvider = try await TropLibraryCombinedBackupService.snapshot()
        precondition(restoredWithoutProvider.libraryV2.aliases.isEmpty)
        precondition(restoredWithoutProvider.libraryV2.legacyRelations.isEmpty)
        precondition(restoredWithoutProvider.legacyAlbumSources.isEmpty)
        precondition(restoredWithoutProvider.legacyArtistSources.isEmpty)
        precondition(
            restoredWithoutProvider.libraryV2.radioFavorites
                == combined.library.libraryV2.radioFavorites
        )
        precondition(
            restoredWithoutProvider.libraryV2.playlistEntries
                == combined.library.libraryV2.playlistEntries
        )
        precondition(
            restoredWithoutProvider.podcastEpisodeMemberships
                == combined.library.podcastEpisodeMemberships
        )
        precondition(restoredWithoutProvider.relatedPodcasts == combined.library.relatedPodcasts)
        precondition(restoredWithoutProvider.relatedEpisodes == combined.library.relatedEpisodes)
        precondition(restoredWithoutProvider.podcastArtists == combined.library.podcastArtists)
        precondition(
            restoredWithoutProvider.episodePodcastNames
                == combined.library.episodePodcastNames
        )
        let withoutProviderExport = try await TropLibraryCombinedBackupService.export()
        let exportedWithoutProvider = try TropLibraryCombinedBackupArchive.decode(
            withoutProviderExport
        )
        precondition(exportedWithoutProvider.library.libraryV2.aliases.isEmpty)
        precondition(
            exportedWithoutProvider.library.libraryV2.radioFavorites
                == combined.library.libraryV2.radioFavorites
        )
        precondition(
            exportedWithoutProvider.library.podcastEpisodeMemberships
                == combined.library.podcastEpisodeMemberships
        )
        precondition(
            exportedWithoutProvider.library.podcastArtists
                == combined.library.podcastArtists
        )
        precondition(
            exportedWithoutProvider.library.episodePodcastNames
                == combined.library.episodePodcastNames
        )
        precondition(!String(decoding: withoutProviderExport, as: UTF8.self).contains("youtube"))
        print("Combined GRDB metadata roundtrip passed without YouTube/provider aliases")

    }
}
