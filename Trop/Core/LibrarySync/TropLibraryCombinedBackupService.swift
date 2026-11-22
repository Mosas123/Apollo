import Foundation
import GRDB

/// Staging-only unified archive service. Nothing is enabled in Settings.
/// Both halves are fetched under ONE GRDB read transaction, so user edits
/// cannot sneak between independent legacy and V2 snapshots.
enum TropLibraryCombinedBackupService {
    struct Preview: Equatable, Sendable {
        let legacyTracks: Int
        let legacyPlaylists: Int
        let legacyPlaylistEntries: Int
        let v2Recordings: Int
        let v2Playlists: Int
        let v2PlaylistEntries: Int
        let radioFavorites: Int
        let omittedPrivateAliases: Int
        let legacyLedgerEntriesNeedingOrigin: Int
        let sourceMemberships: Int
        let ledgerEntriesWithMissingMembership: Int
        let foreignTombstones: Int
        let podcastEpisodeMemberships: Int
        let relatedPodcasts: Int
        let relatedEpisodes: Int
    }

    static func preview(_ data: Data) throws -> Preview {
        let library = try TropLibraryCombinedBackupArchive.decode(data).library
        let membershipIDs = Set(library.legacyMemberships.map(\.sourceRowID))
        return Preview(
            legacyTracks: library.legacy.tracks.count,
            legacyPlaylists: library.legacy.playlists.count,
            legacyPlaylistEntries: library.legacy.playlistEntries.count,
            v2Recordings: library.libraryV2.items.filter { $0.kind == "recording" }.count,
            v2Playlists: library.libraryV2.items.filter { $0.kind == "playlist" }.count,
            v2PlaylistEntries: library.libraryV2.playlistEntries.count,
            radioFavorites: library.libraryV2.radioFavorites.count,
            omittedPrivateAliases: library.libraryV2.omittedPrivateAliases,
            legacyLedgerEntriesNeedingOrigin: library.libraryV2.importLedger.count,
            sourceMemberships: library.legacyMemberships.count,
            ledgerEntriesWithMissingMembership: library.libraryV2.importLedger.filter {
                !membershipIDs.contains($0.legacyMembershipID)
            }.count,
            foreignTombstones: library.foreignTombstones.count,
            podcastEpisodeMemberships: library.podcastEpisodeMemberships.count,
            relatedPodcasts: library.relatedPodcasts.count,
            relatedEpisodes: library.relatedEpisodes.count
        )
    }

    static func snapshot() async throws -> TropLibraryCombinedBackupSnapshot {
        guard DatabaseService.shared.usesPersistentStore else {
            throw TropLibraryCombinedBackupError.temporaryDatabase
        }
        return try await DatabaseService.shared.read { db in
            guard let originScope = try String.fetchOne(
                db, sql: "SELECT origin_scope FROM trop_v2_library_origin WHERE singleton = 1"
            ) else { throw TropLibraryCombinedBackupError.invalidPayload }
            let legacy = try TropLibraryBackupService.snapshot(in: db)
            let v2 = try TropLibraryV2RecoveryStore.snapshot(in: db)
            let memberships = try Row.fetchAll(
                db, sql: """
                    SELECT id, playlist_id, song_id, position
                    FROM playlist_song_map ORDER BY playlist_id, position, id
                    """
            ).map { row in
                TropLibraryCombinedBackupSnapshot.LegacyMembership(
                    sourceRowID: row["id"],
                    playlistID: row["playlist_id"], songID: row["song_id"],
                    position: row["position"]
                )
            }
            let foreignTombstones = try Row.fetchAll(
                db, sql: """
                    SELECT origin_scope, source_membership_id, entry_id, imported_at
                    FROM trop_v2_foreign_import_tombstone
                    ORDER BY origin_scope, source_membership_id
                    """
            ).map { row in
                TropLibraryCombinedBackupSnapshot.ForeignTombstone(
                    originScope: row["origin_scope"],
                    sourceMembershipID: row["source_membership_id"],
                    entryID: row["entry_id"], importedAt: row["imported_at"]
                )
            }
            // Legacy V1 intentionally includes only saved/subscribed rows.
            // Combined V4 also includes unsaved/unsubscribed podcast records
            // referenced by the ordered podcast_episode_map relationship.
            let podcastLinks = try Row.fetchAll(
                db, sql: """
                    SELECT podcast_id, episode_id, position
                    FROM podcast_episode_map
                    ORDER BY podcast_id, position, id
                    """
            ).map { row in
                TropLibraryCombinedBackupSnapshot.PodcastEpisodeMembership(
                    podcastID: row["podcast_id"], episodeID: row["episode_id"],
                    position: row["position"]
                )
            }
            let relatedPodcasts = try Row.fetchAll(
                db, sql: """
                    SELECT id, name, subscribed_at FROM podcast
                    WHERE subscribed_at IS NULL AND EXISTS (
                        SELECT 1 FROM podcast_episode_map AS link
                        WHERE link.podcast_id = podcast.id
                    )
                    ORDER BY id
                    """
            ).map { row in
                TropLibraryCombinedBackupSnapshot.RelatedPodcast(
                    id: row["id"], name: row["name"],
                    subscribedAt: row["subscribed_at"]
                )
            }
            let relatedEpisodes = try Row.fetchAll(
                db, sql: """
                    SELECT id, title, podcast_id, duration, is_played, saved_at
                    FROM episode WHERE saved_at IS NULL AND EXISTS (
                        SELECT 1 FROM podcast_episode_map AS link
                        WHERE link.episode_id = episode.id
                    )
                    ORDER BY id
                    """
            ).map { row in
                TropLibraryCombinedBackupSnapshot.RelatedEpisode(
                    id: row["id"], title: row["title"],
                    podcastID: row["podcast_id"], duration: row["duration"],
                    isPlayed: row["is_played"], savedAt: row["saved_at"]
                )
            }
            return TropLibraryCombinedBackupSnapshot(
                legacy: legacy, libraryV2: v2,
                legacyMemberships: memberships, originScope: originScope,
                foreignTombstones: foreignTombstones,
                relatedPodcasts: relatedPodcasts,
                relatedEpisodes: relatedEpisodes,
                podcastEpisodeMemberships: podcastLinks
            )
        }
    }

    static func export() async throws -> Data {
        let library = try await snapshot()
        return try TropLibraryCombinedBackupArchive.encode(library)
    }
}
