import Foundation
import GRDB

/// A user-visible *rehearsal*, not a recovery operation. Uses a brand-new
/// in-memory SQLite queue created with the app's actual v1...current schema.
/// No File Provider, CloudKit, credentials or live database handle is ever
/// passed to the scratch database.
enum TropLibraryCombinedRestoreRehearsal {
    /// Only fixed diagnostic codes leave this boundary. In particular, never
    /// return a raw SQLite error, SQL arguments, file paths, song names,
    /// provider identifiers or the archive itself to the UI/logs.
    enum Failure: Error, Sendable {
        case archiveVerification
        case scratchSchema
        case scratchRestore
        case scratchReadback
        case scratchOccupiedCheck
        case mismatchedRoundTrip(String)
        case incompleteLegacyLineage

        var diagnosticCode: String {
            switch self {
            case .archiveVerification: "ARCHIVE_VERIFY"
            case .scratchSchema: "SCRATCH_SCHEMA"
            case .scratchRestore: "SCRATCH_RESTORE"
            case .scratchReadback: "SCRATCH_READBACK"
            case .scratchOccupiedCheck: "OCCUPIED_GUARD"
            case .mismatchedRoundTrip(let section): "ROUNDTRIP_" + section
            case .incompleteLegacyLineage: "LINEAGE_COUNT"
            }
        }
    }

    struct Result: Sendable {
        let legacyTracks: Int
        let v2Recordings: Int
        let v2Playlists: Int
        let v2PlaylistEntries: Int
        let radioFavorites: Int
        let withheldPrivateAliases: Int
    }

    /// The archive itself stores timestamps at millisecond resolution. GRDB
    /// serializes Date through its own SQLite date representation. Comparing
    /// Date using binary floating-point equality can report a false mismatch
    /// after a valid roundtrip on a real device. Compare ALL Codable fields,
    /// but canonically round dates to the archive's millisecond resolution.
    static func sameArchiveMetadata<T: Encodable>(
        _ original: T, _ recovered: T
    ) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
            guard milliseconds.isFinite, abs(milliseconds) < 9.0e18 else {
                throw TropLibraryCombinedBackupError.invalidPayload
            }
            try value.encode(Int64(milliseconds))
        }
        guard let lhs = try? encoder.encode(original),
              let rhs = try? encoder.encode(recovered) else {
            return false
        }
        return lhs == rhs
    }

    /// Pure scratch-db restore. Callable from a detached task, never on the
    /// UI thread; the scratch queue cannot escape this function.
    static func rehearse(_ archive: Data) throws -> Result {
        let source: TropLibraryCombinedBackupSnapshot
        let expected: TropLibraryCombinedBackupService.Preview
        do {
            source = try TropLibraryCombinedBackupArchive.decode(archive).library
            expected = try TropLibraryCombinedBackupService.preview(archive)
        } catch {
            throw Failure.archiveVerification
        }

        // This queue is private, nonpersistent, and holds no user data until
        // the already-validated archive is copied to it inside one write.
        let scratch: DatabaseQueue
        do {
            scratch = try DatabaseQueue()
            var migrations = DatabaseMigrator()
            TropDatabaseMigrationSequence.register(&migrations)
            try migrations.migrate(scratch)
        } catch {
            throw Failure.scratchSchema
        }

        let restoredPreview: TropLibraryCombinedBackupService.Preview
        do {
            restoredPreview = try scratch.write { db in
                try TropLibraryCombinedRestoreStore.restoreInTransaction(
                    archive, in: db
                )
            }
        } catch {
            throw Failure.scratchRestore
        }
        guard restoredPreview == expected else {
            throw Failure.mismatchedRoundTrip("PREVIEW")
        }

        let restored: TropLibraryCombinedBackupSnapshot
        do {
            restored = try scratch.read { db in
                try TropLibraryCombinedBackupService.snapshot(in: db)
            }
        } catch {
            throw Failure.scratchReadback
        }

        // Compare the content that is actually recoverable. The origin scope
        // is intentionally installation-specific; SQLite membership IDs can
        // differ after restore. Omitted private aliases cannot be recreated.
        // Compare each preserved section to identify the failure precisely.
        let sections: [(String, Bool)] = [
            ("LEGACY", sameArchiveMetadata(source.legacy, restored.legacy)),
            ("ALBUM_SOURCES", source.legacyAlbumSources == restored.legacyAlbumSources),
            ("ARTIST_SOURCES", source.legacyArtistSources == restored.legacyArtistSources),
            ("PODCAST_ARTISTS", source.podcastArtists == restored.podcastArtists),
            ("EPISODE_NAMES", source.episodePodcastNames == restored.episodePodcastNames),
            ("RELATED_PODCASTS", sameArchiveMetadata(source.relatedPodcasts, restored.relatedPodcasts)),
            ("RELATED_EPISODES", sameArchiveMetadata(source.relatedEpisodes, restored.relatedEpisodes)),
            ("PODCAST_LINKS", source.podcastEpisodeMemberships == restored.podcastEpisodeMemberships),
            ("V2_ITEMS", sameArchiveMetadata(source.libraryV2.items, restored.libraryV2.items)),
            ("V2_ALIASES", source.libraryV2.aliases == restored.libraryV2.aliases),
            ("V2_ENTRIES", sameArchiveMetadata(source.libraryV2.playlistEntries, restored.libraryV2.playlistEntries)),
            ("V2_RADIO", sameArchiveMetadata(source.libraryV2.radioFavorites, restored.libraryV2.radioFavorites)),
            ("V2_RELATIONS", sameArchiveMetadata(source.libraryV2.legacyRelations, restored.libraryV2.legacyRelations)),
            ("MEMBERSHIP_COUNT", source.legacyMemberships.count == restored.legacyMemberships.count)
        ]
        if let failingSection = sections.first(where: { !$0.1 }) {
            throw Failure.mismatchedRoundTrip(failingSection.0)
        }

        let sourceLineage = source.libraryV2.importLedger.count
            + source.foreignTombstones.count
        let restoredLineage = restored.libraryV2.importLedger.count
            + restored.foreignTombstones.count
        guard sourceLineage == restoredLineage else {
            throw Failure.incompleteLegacyLineage
        }

        // Prove a repeated restore cannot overwrite the scratch destination.
        do {
            _ = try scratch.write { db in
                try TropLibraryCombinedRestoreStore.restoreInTransaction(
                    archive, in: db
                )
            }
            throw Failure.scratchOccupiedCheck
        } catch TropLibraryCombinedRestorePreflight.Blocker.occupiedDestination {
            // Correct behavior.
        } catch {
            throw Failure.scratchOccupiedCheck
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
