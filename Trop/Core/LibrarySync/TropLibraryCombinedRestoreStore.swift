import Foundation
import GRDB

/// INTERNAL staging implementation for an empty-destination combined restore.
/// No settings route, no user-facing restore action, no remote account access.
/// DatabaseService.write supplies one atomic GRDB transaction; any thrown
/// failure rolls back BOTH legacy and V2 mutations.
enum TropLibraryCombinedRestoreStore {
    enum Blocker: Error, Equatable, Sendable {
        case temporaryDatabase
        case unresolvedLegacyMembership
    }

    /// Not a complete rescue: downloaded audio, login credentials, caches,
    /// history and private addon identifiers are intentionally excluded.
    /// Restore refuses occupied databases; orphan ledger history is namespaced.
    static func restoreIntoEmptyLibrary(
        _ archive: Data
    ) async throws -> TropLibraryCombinedBackupService.Preview {
        guard DatabaseService.shared.usesPersistentStore else {
            throw Blocker.temporaryDatabase
        }
        return try await DatabaseService.shared.writeReturning { db in
            try restoreInTransaction(archive, in: db)
        }
    }

    /// The same actual SQL path can run against a separate in-memory queue.
    /// Caller owns the one GRDB write transaction and the destination DB;
    /// NEVER pass the shared live DB from an experimental UI rehearsal.
    static func restoreInTransaction(
        _ archive: Data, in db: Database
    ) throws -> TropLibraryCombinedBackupService.Preview {
        let source = try TropLibraryCombinedBackupArchive.decode(archive).library
        let preview = try TropLibraryCombinedBackupService.preview(archive)
        let trackIDs = Set(source.legacy.tracks.map(\.id))
        let playlistIDs = Set(source.legacy.playlists.map(\.id))
        guard source.legacy.playlistEntries.allSatisfy({
            trackIDs.contains($0.songId) && playlistIDs.contains($0.playlistId)
        }) else {
            throw Blocker.unresolvedLegacyMembership
        }

        // Must be checked INSIDE this exact transaction. Never truncate,
        // reset, merge into, or overwrite a user's existing database.
        try TropLibraryCombinedRestorePreflight.requireEmpty(db)

            for item in source.legacy.tracks {
                try db.execute(
                    sql: """
                        INSERT INTO song
                            (id, title, artist_name, album_name, duration,
                             liked, in_library, is_episode, create_date, modify_date)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        item.id, item.title, item.artistName, item.albumName,
                        item.duration, item.liked, item.inLibrary,
                        item.isEpisode, item.createdAt, item.createdAt
                    ]
                )
            }
            for album in source.legacy.albums {
                try db.execute(
                    sql: "INSERT INTO album (id, title, bookmarked_at) VALUES (?, ?, ?)",
                    arguments: [album.id, album.title, album.bookmarkedAt]
                )
            }
            for artist in source.legacy.artists {
                try db.execute(
                    sql: "INSERT INTO artist (id, name, bookmarked_at) VALUES (?, ?, ?)",
                    arguments: [artist.id, artist.name, artist.bookmarkedAt]
                )
            }
            // Provider pointers belong to saved album/artist rows. They are
            // restored only as optional legacy metadata; V2 playback must
            // resolve providers independently and work without YouTube.
            for sourceLink in source.legacyAlbumSources {
                try db.execute(
                    sql: "UPDATE album SET playlist_id = ? WHERE id = ?",
                    arguments: [sourceLink.sourcePlaylistID, sourceLink.albumID]
                )
            }
            for sourceLink in source.legacyArtistSources {
                try db.execute(
                    sql: "UPDATE artist SET channel_id = ? WHERE id = ?",
                    arguments: [sourceLink.sourceChannelID, sourceLink.artistID]
                )
            }
            // Only the local is_podcast_channel classification is restored.
            // This neither authenticates nor starts any provider sync.
            for artistFlag in source.podcastArtists {
                try db.execute(
                    sql: "UPDATE artist SET is_podcast_channel = 1 WHERE id = ?",
                    arguments: [artistFlag.artistID]
                )
            }
            for list in source.legacy.playlists {
                try db.execute(
                    sql: """
                        INSERT INTO playlist
                            (id, name, browse_id, bookmarked_at, is_editable)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        list.id, list.name, list.browseId,
                        list.bookmarkedAt, list.isEditable
                    ]
                )
            }
            for podcast in source.legacy.podcasts {
                try db.execute(
                    sql: """
                        INSERT INTO podcast (id, name, subscribed_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [podcast.id, podcast.name, podcast.subscribedAt]
                )
            }
            for episode in source.legacy.episodes {
                try db.execute(
                    sql: """
                        INSERT INTO episode
                            (id, title, podcast_id, duration, is_played, saved_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        episode.id, episode.title, episode.podcastId,
                        episode.duration, episode.isPlayed, episode.savedAt
                    ]
                )
            }

            // Restore the extra unsaved/unsubscribed podcast entities without
            // inventing subscription dates, and then their exact ordering.
            for podcast in source.relatedPodcasts {
                try db.execute(
                    sql: """
                        INSERT INTO podcast (id, name, subscribed_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [podcast.id, podcast.name, podcast.subscribedAt]
                )
            }
            for episode in source.relatedEpisodes {
                try db.execute(
                    sql: """
                        INSERT INTO episode
                            (id, title, podcast_id, duration, is_played, saved_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        episode.id, episode.title, episode.podcastID,
                        episode.duration, episode.isPlayed, episode.savedAt
                    ]
                )
            }
            for link in source.podcastEpisodeMemberships {
                try db.execute(
                    sql: """
                        INSERT INTO podcast_episode_map
                            (podcast_id, episode_id, position)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [link.podcastID, link.episodeID, link.position]
                )
            }

            // Restore validated display names only after saved and related
            // episodes exist. A human-readable title does not require
            // a provider session, a podcast feed URL or source credentials.
            for name in source.episodePodcastNames {
                try db.execute(
                    sql: "UPDATE episode SET podcast_name = ? WHERE id = ?",
                    arguments: [name.podcastName, name.episodeID]
                )
            }

            // The destination assigns new local row IDs. Store the exact
            // source-to-destination association before restoring V2's ledger.
            var inserted: [TropLibraryCombinedRestorePlanner.DestinationMembership] = []
            inserted.reserveCapacity(source.legacyMemberships.count)
            for membership in source.legacyMemberships {
                try db.execute(
                    sql: """
                        INSERT INTO playlist_song_map
                            (playlist_id, song_id, position)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [
                        membership.playlistID, membership.songID,
                        membership.position
                    ]
                )
                inserted.append(.init(
                    sourceRowID: membership.sourceRowID,
                    assignedRowID: db.lastInsertedRowID,
                    playlistID: membership.playlistID,
                    songID: membership.songID,
                    position: membership.position
                ))
            }

            // Throws on orphan/tombstoned IDs, ambiguous mappings, corrupted
            // archives, and incorrect song/playlist identity. A throw here
            // must roll back all prior legacy inserts.
            let mapping = try TropLibraryCombinedRestorePlanner.prepare(
                archive: archive, insertedMemberships: inserted
            )

            for item in source.libraryV2.items {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_item
                            (id, kind, title, artist_or_author, duration_seconds,
                             saved_at, liked_at, created_at, modified_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        item.id, item.kind, item.title, item.artistOrAuthor,
                        item.durationSeconds, item.savedAt, item.likedAt,
                        item.createdAt, item.modifiedAt
                    ]
                )
            }
            for alias in source.libraryV2.aliases {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_source_alias
                            (id, item_id, kind, provider, source_scope, external_id)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        alias.id, alias.itemID, alias.kind, alias.provider,
                        alias.scope, alias.externalID
                    ]
                )
            }
            for entry in source.libraryV2.playlistEntries {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_playlist_entry
                            (id, playlist_id, recording_id, position, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        entry.id, entry.playlistID, entry.recordingID,
                        entry.position, entry.createdAt
                    ]
                )
            }
            for radio in source.libraryV2.radioFavorites {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_radio_favorite
                            (id, station_uuid, name, subtitle, added_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        radio.id, radio.stationUUID, radio.name,
                        radio.subtitle, radio.addedAt
                    ]
                )
            }
            for ledger in mapping.remappedImportLedger {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_legacy_import_entry
                            (legacy_membership_id, entry_id, imported_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [
                        ledger.legacyMembershipID, ledger.entryID,
                        ledger.importedAt
                    ]
                )
            }
            for tombstone in mapping.foreignTombstones {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_foreign_import_tombstone
                            (origin_scope, source_membership_id, entry_id, imported_at)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [
                        tombstone.originScope, tombstone.sourceMembershipID,
                        tombstone.entryID, tombstone.importedAt
                    ]
                )
            }
            for link in source.libraryV2.legacyRelations {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_legacy_relation
                            (id, owner_item_id, link_kind, external_id, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        link.id, link.ownerItemID, link.linkKind,
                        link.externalID, link.createdAt
                    ]
                )
            }
        return preview
    }
}
