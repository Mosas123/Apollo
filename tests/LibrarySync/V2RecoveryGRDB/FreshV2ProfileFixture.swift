import Foundation
import GRDB

/// Replays the *shape* observed on the user's iPhone: zero legacy records,
/// 24 V2 recordings and 10 playlist occurrences. ALL names and IDs below are
/// synthetic. No user snapshot or production database is needed for this test.
extension RecoveryFixture {
    static func checkFreshV2ProfileCombinedRoundTrip() async throws {
        let playlistID = "c0000000-0000-4000-8000-00000000ffff"
        // A real iPhone records Date values with fractional milliseconds.
        // Unlike the former whole-second fixture this reproduces precision
        // changes between GRDB's SQLite dates and archive JSON.
        let recordedAt = now.addingTimeInterval(0.123456)

        @Sendable func stableID(_ sequence: Int) -> String {
            "c0000000-0000-4000-8000-" + String(format: "%012x", sequence)
        }

        // Dispose of the earlier synthetic migration fixture. Production
        // restore and migration have NO deletion or reset path.
        try await DatabaseService.shared.write { db in
            for table in [
                "trop_v2_legacy_import_entry",
                "trop_v2_foreign_import_tombstone",
                "trop_v2_playlist_entry",
                "trop_v2_source_alias",
                "trop_v2_legacy_relation",
                "trop_v2_radio_favorite",
                "trop_v2_item",
                "playlist_song_map",
                "podcast_episode_map",
                "song", "album", "artist", "playlist", "podcast", "episode"
            ] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            try TropLibraryCombinedRestorePreflight.requireEmpty(db)

            // No YouTube/other provider aliases and no legacy source rows.
            // The V2 ownership model itself must be enough for recovery.
            for index in 1...24 {
                try db.execute(sql: """
                    INSERT INTO trop_v2_item
                        (id, kind, title, artist_or_author, duration_seconds,
                         saved_at, liked_at, created_at, modified_at)
                    VALUES (?, 'recording', ?, 'Synthetic Artist', 180,
                            ?, ?, ?, ?)
                    """, arguments: [
                        stableID(index),
                        "Synthetic Recording \(index)",
                        recordedAt,
                        index <= 12 ? recordedAt : nil,
                        recordedAt,
                        recordedAt
                    ])
            }
            try db.execute(sql: """
                INSERT INTO trop_v2_item
                    (id, kind, title, duration_seconds, saved_at,
                     created_at, modified_at)
                VALUES (?, 'playlist', 'Synthetic Playlist', 0, ?, ?, ?)
                """, arguments: [playlistID, recordedAt, recordedAt, recordedAt])

            for position in 0..<10 {
                // Intentionally duplicate several recording references; the
                // original V2 playlist membership count is 10, not 10 songs.
                let recordingID = stableID((position % 6) + 1)
                try db.execute(sql: """
                    INSERT INTO trop_v2_playlist_entry
                        (id, playlist_id, recording_id, position, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [
                        stableID(position + 101), playlistID,
                        recordingID, position, recordedAt
                    ])
            }
        }

        let source = try await TropLibraryCombinedBackupService.snapshot()
        let encoded = try await TropLibraryCombinedBackupService.export()
        let summary = try TropLibraryCombinedBackupService.preview(encoded)
        precondition(summary.legacyTracks == 0)
        precondition(summary.legacyPlaylists == 0)
        precondition(summary.legacyPlaylistEntries == 0)
        precondition(summary.v2Recordings == 24)
        precondition(summary.v2Playlists == 1)
        precondition(summary.v2PlaylistEntries == 10)
        precondition(summary.omittedPrivateAliases == 0)
        precondition(source.libraryV2.aliases.isEmpty)

        // Rehearse using the SAME v1...v13 production migration sequence
        // inside a brand-new, private in-memory SQLite database.
        let rehearsal = try TropLibraryCombinedRestoreRehearsal.rehearse(encoded)
        precondition(rehearsal.legacyTracks == 0)
        precondition(rehearsal.v2Recordings == 24)
        precondition(rehearsal.v2Playlists == 1)
        precondition(rehearsal.v2PlaylistEntries == 10)
        let liveFixtureAfterRehearsal =
            try await TropLibraryCombinedBackupService.snapshot()
        precondition(liveFixtureAfterRehearsal == source,
                     "In-memory rehearsal mutated the source database")
        precondition(
            source.libraryV2.playlistEntries.map(\.position) == Array(0..<10),
            "Original playlist order is not stable"
        )

        // Exported archive must be self-consistent and tampering must fail
        // before a restoration can write even one row.
        let rawJSON = String(decoding: encoded, as: UTF8.self)
        let tampered = rawJSON.replacingOccurrences(
            of: "Synthetic Recording 1", with: "Corrupted Recording 1"
        )
        precondition(tampered != rawJSON)
        do {
            _ = try TropLibraryCombinedBackupArchive.decode(
                Data(tampered.utf8)
            )
            preconditionFailure("Tampered combined archive was accepted")
        } catch TropLibraryCombinedBackupError.checksumMismatch {
            // Expected.
        }

        // Clear ONLY the disposable test DB, never app/user storage.
        try await DatabaseService.shared.write { db in
            for table in [
                "trop_v2_legacy_import_entry",
                "trop_v2_foreign_import_tombstone",
                "trop_v2_playlist_entry",
                "trop_v2_source_alias",
                "trop_v2_legacy_relation",
                "trop_v2_radio_favorite",
                "trop_v2_item"
            ] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            try TropLibraryCombinedRestorePreflight.requireEmpty(db)
        }

        let restoredSummary =
            try await TropLibraryCombinedRestoreStore.restoreIntoEmptyLibrary(
                encoded
            )
        precondition(restoredSummary == summary)
        let restored = try await TropLibraryCombinedBackupService.snapshot()
        precondition(restored.legacy == source.legacy)
        let archivedSource = try TropLibraryCombinedBackupArchive.decode(encoded).library
        precondition(
            TropLibraryCombinedRestoreRehearsal.sameArchiveMetadata(
                restored.libraryV2.items, archivedSource.libraryV2.items
            ),
            "Real-world subsecond dates must survive archive-level roundtrip"
        )
        precondition(
            TropLibraryCombinedRestoreRehearsal.sameArchiveMetadata(
                restored.libraryV2.playlistEntries,
                archivedSource.libraryV2.playlistEntries
            ),
            "Playlist occurrences or order changed across recovery"
        )
        precondition(restored.libraryV2.aliases.isEmpty)
        precondition(restored.libraryV2.items.count == 25)
        precondition(restored.libraryV2.playlistEntries.count == 10)
        let afterExport = try await TropLibraryCombinedBackupService.export()
        let after = try TropLibraryCombinedBackupArchive.decode(afterExport)
        precondition(
            TropLibraryCombinedRestoreRehearsal.sameArchiveMetadata(
                after.library.libraryV2.items, archivedSource.libraryV2.items
            )
        )
        precondition(
            TropLibraryCombinedRestoreRehearsal.sameArchiveMetadata(
                after.library.libraryV2.playlistEntries,
                archivedSource.libraryV2.playlistEntries
            )
        )

        // A second restore on the occupied DB must fail closed and leave the
        // already-reconstructed collection untouched.
        do {
            _ = try await TropLibraryCombinedRestoreStore.restoreIntoEmptyLibrary(
                encoded
            )
            preconditionFailure("Restore overwrote a nonempty V2 library")
        } catch TropLibraryCombinedRestorePreflight.Blocker.occupiedDestination {
            // Expected; no overwrite, reset or destructive merge.
        }
        let unchanged = try await TropLibraryCombinedBackupService.snapshot()
        precondition(unchanged.libraryV2 == restored.libraryV2)
        print(
            "Fresh V2 profile combined GRDB roundtrip passed: "
                + "0 legacy, 24 recordings, 10 ordered playlist entries, "
                + "no provider aliases, tamper rejection, occupied-DB protection"
        )
    }
}
