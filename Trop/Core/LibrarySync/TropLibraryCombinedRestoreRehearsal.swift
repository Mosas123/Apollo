import Foundation
import GRDB

/// A user-visible *rehearsal*, not a recovery operation. Uses a brand-new
/// in-memory SQLite queue created with the app's actual v1...current schema.
/// No File Provider, CloudKit, credentials or DatabaseService.shared database
/// handle is ever passed to the scratch database.
enum TropLibraryCombinedRestoreRehearsal {
    enum Failure: Error, Sendable {
        case mismatchedRoundTrip
        case incompleteLegacyLineage
    }

    struct Result: Sendable {
        let legacyTracks: Int
        let v2Recordings: Int
        let v2Playlists: Int
        let v2PlaylistEntries: Int
        let radioFavorites: Int
        let withheldPrivateAliases: Int
    }

    /// This synchronous operation can be called from Task.detached to avoid
    /// blocking the UI thread. Input is bounded and validated before the
    /// scratch schema is created. The queue never escapes this function.
    static func rehearse(_ archive: Data) throws -> Result {
        let envelope = try TropLibraryCombinedBackupArchive.decode(archive)
        let source = envelope.library
        let expected = try TropLibraryCombinedBackupService.preview(archive)

        // This is an entirely separate, empty, memory-only database.
        let scratch = try DatabaseQueue()
        var migrations = DatabaseMigrator()
        TropDatabaseMigrationSequence.register(&migrations)
        try migrations.migrate(scratch)

        // Reuse *exactly* the production restoration SQL. Both preflight and
        // inserts execute inside this sole scratch-db write transaction.
        let restoredPreview = try scratch.write { db in
            try TropLibraryCombinedRestoreStore.restoreInTransaction(
                archive, in: db
            )
        }
        guard restoredPreview == expected else {
            throw Failure.mismatchedRoundTrip
        }

        // Read back all serialized metadata from the scratch queue. No data
        // is fetched from the user's actual on-device database.
        let restored = try scratch.read { db in
            try TropLibraryCombinedBackupService.snapshot(in: db)
        }

        // Restore a provider-independent V2 user collection without changing
        // IDs, playlist occurrence order, likes, radio or podcast metadata.
        guard restored.legacy == source.legacy,
              restored.legacyAlbumSources == source.legacyAlbumSources,
              restored.legacyArtistSources == source.legacyArtistSources,
              restored.podcastArtists == source.podcastArtists,
              restored.episodePodcastNames == source.episodePodcastNames,
              restored.relatedPodcasts == source.relatedPodcasts,
              restored.relatedEpisodes == source.relatedEpisodes,
              restored.podcastEpisodeMemberships == source.podcastEpisodeMemberships,
              restored.libraryV2.items == source.libraryV2.items,
              restored.libraryV2.aliases == source.libraryV2.aliases,
              restored.libraryV2.playlistEntries == source.libraryV2.playlistEntries,
              restored.libraryV2.radioFavorites == source.libraryV2.radioFavorites,
              restored.libraryV2.legacyRelations == source.libraryV2.legacyRelations,
              restored.legacyMemberships.count == source.legacyMemberships.count
        else {
            throw Failure.mismatchedRoundTrip
        }

        // SQLite membership IDs are *database-local*. Existing live links
        // must be remapped and orphaned history namespaced as tombstones.
        // Their numeric source IDs are NOT required to equal destination IDs.
        let sourceLineage = source.libraryV2.importLedger.count
            + source.foreignTombstones.count
        let restoredLineage = restored.libraryV2.importLedger.count
            + restored.foreignTombstones.count
        guard sourceLineage == restoredLineage else {
            throw Failure.incompleteLegacyLineage
        }

        // A repeated write on an occupied scratch library must be refused
        // before touching a single existing row. Never reset or overwrite.
        do {
            _ = try scratch.write { db in
                try TropLibraryCombinedRestoreStore.restoreInTransaction(
                    archive, in: db
                )
            }
            throw Failure.mismatchedRoundTrip
        } catch TropLibraryCombinedRestorePreflight.Blocker.occupiedDestination {
            // Expected. The first restoration remains intact in the sandbox.
        }

        return Result(
            legacyTracks: expected.legacyTracks,
            v2Recordings: expected.v2Recordings,
            v2Playlists: expected.v2Playlists,
            v2PlaylistEntries: expected.v2PlaylistEntries,
            radioFavorites: expected.radioFavorites,
            withheldPrivateAliases: expected.omittedPrivateAliases
        )
    }
}
