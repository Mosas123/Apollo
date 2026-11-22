import Foundation
import GRDB

/// Real production importer exercised against the disposable GRDB fixture.
/// This never runs inside the app, and the fixture's legacy data is synthetic.
extension RecoveryFixture {
    static func checkProductionLegacyImporter() async throws {
        // The earlier combined recovery test restored both the original
        // legacy collection and an independent Trop-owned V2 library.
        // Preserve the latter to prove that import is additive.
        let originalV2 = try await DatabaseService.shared.read { db in
            try String.fetchOne(
                db, sql: "SELECT title FROM trop_v2_item WHERE id = ?",
                arguments: [recording]
            )
        }
        precondition(originalV2 == "Una Canción")

        // Prior recovery tests deliberately restored synthetic lineage
        // unrelated to this imported legacy playlist. Clear ONLY that test
        // ledger, not the existing Trop-owned items/playlist/radios.
        // Production migration never resets lineage or deletes user data.
        // The legacy map stores occurrences, not unique song identities.
        // Duplicate an entry on purpose, with a distinct source row ID.
        try await DatabaseService.shared.write { db in
            try db.execute(sql: "DELETE FROM trop_v2_legacy_import_entry")
            // The previous no-provider restore intentionally stripped album
            // catalogue hints. Restore ONE harmless synthetic album relation
            // here so the real importer exercises album + episode links.
            // This affects only the disposable GRDB fixture, never user data.
            try db.execute(sql: """
                UPDATE album SET playlist_id = 'OL-album-fixture'
                WHERE id = 'legacy-album'
                """)
            try db.execute(sql: """
                INSERT INTO playlist_song_map
                    (id, playlist_id, song_id, position)
                VALUES (2222, 'old-playlist', 'legacy-keep', 1)
                """)
        }

        // A preflight must expose the exact expected importer action without
        // performing a single SQLite write or modifying existing V2 rows.
        let beforeDryRun = try await DatabaseService.shared.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trop_v2_item") ?? -1
        }
        let freshPlan = try await TropLibraryV2MigrationDryRun.load()
        precondition(freshPlan.newItems == 6 && freshPlan.reusedItems == 0)
        precondition(freshPlan.newEntries == 2 && freshPlan.existingEntries == 0)
        precondition(!freshPlan.hasBlockers)
        let afterDryRun = try await DatabaseService.shared.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trop_v2_item") ?? -1
        }
        precondition(beforeDryRun == afterDryRun, "Read-only dry run wrote data")

        let first = try await TropLibraryV2LegacyImporter.importLegacySnapshot()
        precondition(first.createdItems == 6, "Expected six distinct legacy entities")
        precondition(first.createdEntries == 2, "Duplicate legacy occurrences lost")
        precondition(first.createdRelations == 2, "Album/episode relations lost")
        precondition(first.reusedItems == 0)

        let migratedSongID = try await DatabaseService.shared.read { db -> String in
            let value = try String.fetchOne(db, sql: """
                SELECT item_id FROM trop_v2_source_alias
                WHERE kind = 'recording' AND provider = 'youtube'
                  AND source_scope = 'global' AND external_id = 'legacy-keep'
                """)
            guard let value else { preconditionFailure("Missing migrated identity") }
            return value
        }

        // A copied YouTube ID is a provenance alias, not a canonical UUID.
        precondition(migratedSongID != "legacy-keep")
        precondition(TropLibraryV2IdentityPolicy.isCanonicalID(migratedSongID))
        try await DatabaseService.shared.read { db in
            let playlistID = try String.fetchOne(db, sql: """
                SELECT item_id FROM trop_v2_source_alias
                WHERE kind = 'playlist' AND provider = 'youtube'
                  AND source_scope = 'global' AND external_id = 'old-playlist'
                """)
            guard let playlistID else {
                preconditionFailure("Missing imported playlist")
            }
            let positions = try Int.fetchAll(db, sql: """
                SELECT position FROM trop_v2_playlist_entry
                WHERE playlist_id = ? ORDER BY position
                """, arguments: [playlistID])
            precondition(positions == [0, 1], "Playlist order/duplicates changed")
            let occurrences = try String.fetchAll(db, sql: """
                SELECT recording_id FROM trop_v2_playlist_entry
                WHERE playlist_id = ? ORDER BY position
                """, arguments: [playlistID])
            precondition(occurrences == [migratedSongID, migratedSongID])
            let untouched = try String.fetchOne(
                db, sql: "SELECT title FROM trop_v2_item WHERE id = ?",
                arguments: [recording]
            )
            precondition(untouched == originalV2, "Existing V2 metadata overwritten")
            let legacyTitle = try String.fetchOne(
                db, sql: "SELECT title FROM song WHERE id = 'legacy-keep'"
            )
            precondition(legacyTitle == "Legacy song preserved")
        }

        // The user edits a migrated recording after the first import.
        // Replaying the old snapshot must not undo that edit or re-add likes.
        try await DatabaseService.shared.write { db in
            try db.execute(sql: """
                UPDATE trop_v2_item SET title = 'User chose a new title',
                    liked_at = NULL WHERE id = ?
                """, arguments: [migratedSongID])
        }
        let replayPlan = try await TropLibraryV2MigrationDryRun.load()
        precondition(replayPlan.newItems == 0 && replayPlan.reusedItems == 6)
        precondition(replayPlan.newEntries == 0 && replayPlan.existingEntries == 2)
        precondition(!replayPlan.hasBlockers)
        let replay = try await TropLibraryV2LegacyImporter.importLegacySnapshot()
        precondition(replay.createdItems == 0 && replay.createdEntries == 0)
        precondition(replay.reusedItems == 6 && replay.existingEntries == 2)
        try await DatabaseService.shared.read { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT title, liked_at FROM trop_v2_item WHERE id = ?",
                arguments: [migratedSongID]
            )
            guard let row else { preconditionFailure("Migrated recording disappeared") }
            let title: String = row["title"]
            let likedAt: Date? = row["liked_at"]
            let isUnliked = likedAt == nil
            precondition(title == "User chose a new title" && isUnliked)
        }

        // When a user deletes one membership, its ledger tombstone prevents
        // importing that occurrence again while retaining the other one.
        try await DatabaseService.shared.write { db in
            guard let deletedEntry = try String.fetchOne(db, sql: """
                SELECT entry_id FROM trop_v2_legacy_import_entry
                WHERE legacy_membership_id = 2222
                """) else { preconditionFailure("Missing occurrence ledger") }
            try db.execute(sql: """
                UPDATE trop_v2_legacy_import_entry
                SET entry_id = NULL WHERE legacy_membership_id = 2222
                """)
            try db.execute(
                sql: "DELETE FROM trop_v2_playlist_entry WHERE id = ?",
                arguments: [deletedEntry]
            )
        }
        let removalPlan = try await TropLibraryV2MigrationDryRun.load()
        precondition(removalPlan.existingEntries == 1)
        precondition(removalPlan.userRemovedEntries == 1)
        precondition(!removalPlan.hasBlockers)
        let afterRemoval = try await TropLibraryV2LegacyImporter.importLegacySnapshot()
        precondition(afterRemoval.createdEntries == 0)
        precondition(afterRemoval.existingEntries == 1)
        precondition(afterRemoval.userRemovedEntries == 1)

        // Insert an initially valid new legacy recording and a malformed
        // record that sorts after it. Failure must roll back the valid V2
        // insert and all aliases, without deleting legacy source records.
        let beforeFailure = try await DatabaseService.shared.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trop_v2_item") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trop_v2_source_alias") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trop_v2_playlist_entry") ?? -1
            )
        }
        try await DatabaseService.shared.write { db in
            try db.execute(sql: """
                INSERT INTO song
                    (id, title, artist_name, duration, liked, is_episode, create_date)
                VALUES ('aaa-valid-new', 'New but must rollback', 'Test', 130, 1, 0, ?),
                       ('zzz-invalid-new', '   ', 'Test', 130, 1, 0, ?)
                """, arguments: [now, now])
        }
        let invalidPlan = try await TropLibraryV2MigrationDryRun.load()
        precondition(invalidPlan.invalidItems == 1)
        precondition(invalidPlan.newItems == 1 && invalidPlan.hasBlockers)
        do {
            _ = try await TropLibraryV2LegacyImporter.importLegacySnapshot()
            preconditionFailure("Malformed legacy record unexpectedly imported")
        } catch TropLibraryV2ValidationError.invalidTitle {
            // Expected validation failure. Verify full transaction rollback.
        }
        let afterFailure = try await DatabaseService.shared.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trop_v2_item") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trop_v2_source_alias") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trop_v2_playlist_entry") ?? -1
            )
        }
        precondition(beforeFailure.0 == afterFailure.0)
        precondition(beforeFailure.1 == afterFailure.1)
        precondition(beforeFailure.2 == afterFailure.2)
        try await DatabaseService.shared.read { db in
            let insertedAlias = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM trop_v2_source_alias
                WHERE external_id = 'aaa-valid-new'
                """) ?? -1
            precondition(insertedAlias == 0, "Partial source alias survived rollback")
            let sourceStillPresent = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM song
                WHERE id IN ('aaa-valid-new', 'zzz-invalid-new')
                """) ?? -1
            precondition(sourceStillPresent == 2, "Legacy rows were modified")
        }

        // A broken playlist member is a separate hard blocker. It should be
        // reported by the read-only scan without mutating the legacy table.
        try await DatabaseService.shared.write { db in
            try db.execute(sql: """
                INSERT INTO playlist_song_map (id, playlist_id, song_id, position)
                VALUES (3222, 'old-playlist', 'not-in-song', 2)
                """)
        }
        let orphanPlan = try await TropLibraryV2MigrationDryRun.load()
        precondition(orphanPlan.unresolvedMemberships == 1)
        precondition(orphanPlan.hasBlockers)
        print("Production GRDB migration dry-run passed: fresh, replay, tombstones, invalid rows and orphan blockers")
        print("Production GRDB legacy importer passed: duplicates, replay, user edits, deletion tombstones and atomic rollback")
    }
}
