import Foundation
import GRDB

/// A consistent GRDB read snapshot. SELECT is deliberately column-limited:
/// never serialize SongEntity wholesale (it contains YouTube mutation tokens),
/// downloaded_track.local_path, format.playback_url, cookies, or event logs.
enum TropLibraryBackupService {
    /// All legacy metadata is read from the caller's transaction.
    /// This is also used by the combined V1+V2 snapshot reader, which
    /// must never collect legacy and V2 rows in separate reads.
    static func snapshot(in db: Database) throws -> TropLibraryBackupSnapshot {
            let tracks = try Row.fetchAll(db, sql: """
                SELECT id, title, artist_name, album_name, duration, liked,
                       in_library, is_episode, create_date
                FROM song
                WHERE liked = 1 OR in_library IS NOT NULL
                   OR EXISTS (
                       SELECT 1 FROM playlist_song_map AS entry
                       WHERE entry.song_id = song.id
                   )
                ORDER BY id
                """).map { row in
                TropLibraryBackupSnapshot.Track(
                    id: row["id"],
                    title: row["title"],
                    artistName: row["artist_name"],
                    albumName: row["album_name"],
                    duration: row["duration"],
                    liked: row["liked"],
                    inLibrary: row["in_library"],
                    isEpisode: row["is_episode"],
                    createdAt: row["create_date"]
                )
            }
            let albums = try Row.fetchAll(db, sql: """
                SELECT id, title, bookmarked_at FROM album
                WHERE bookmarked_at IS NOT NULL ORDER BY id
                """).map { row in
                TropLibraryBackupSnapshot.Album(
                    id: row["id"], title: row["title"],
                    bookmarkedAt: row["bookmarked_at"]
                )
            }
            let artists = try Row.fetchAll(db, sql: """
                SELECT id, name, bookmarked_at FROM artist
                WHERE bookmarked_at IS NOT NULL ORDER BY id
                """).map { row in
                TropLibraryBackupSnapshot.Artist(
                    id: row["id"], name: row["name"],
                    bookmarkedAt: row["bookmarked_at"]
                )
            }
            // Keep all existing playlists and entries, including the legacy
            // unbookmarked rows: remote refreshes have previously changed the
            // bookmark flag, and a backup must not silently discard metadata.
            let playlists = try Row.fetchAll(db, sql: """
                SELECT id, name, browse_id, bookmarked_at, is_editable
                FROM playlist ORDER BY id
                """).map { row in
                TropLibraryBackupSnapshot.Playlist(
                    id: row["id"], name: row["name"],
                    browseId: row["browse_id"],
                    bookmarkedAt: row["bookmarked_at"],
                    isEditable: row["is_editable"]
                )
            }
            let playlistEntries = try Row.fetchAll(db, sql: """
                SELECT playlist_id, song_id, position
                FROM playlist_song_map
                ORDER BY playlist_id, position, id
                """).map { row in
                TropLibraryBackupSnapshot.PlaylistEntry(
                    playlistId: row["playlist_id"],
                    songId: row["song_id"],
                    position: row["position"]
                )
            }
            let podcasts = try Row.fetchAll(db, sql: """
                SELECT id, name, subscribed_at FROM podcast
                WHERE subscribed_at IS NOT NULL ORDER BY id
                """).map { row in
                TropLibraryBackupSnapshot.Podcast(
                    id: row["id"], name: row["name"],
                    subscribedAt: row["subscribed_at"]
                )
            }
            let episodes = try Row.fetchAll(db, sql: """
                SELECT id, title, podcast_id, duration, is_played, saved_at
                FROM episode
                WHERE saved_at IS NOT NULL ORDER BY id
                """).map { row in
                TropLibraryBackupSnapshot.Episode(
                    id: row["id"], title: row["title"],
                    podcastId: row["podcast_id"],
                    duration: row["duration"],
                    isPlayed: row["is_played"],
                    savedAt: row["saved_at"]
                )
            }
            return TropLibraryBackupSnapshot(
                tracks: tracks, albums: albums, artists: artists,
                playlists: playlists, playlistEntries: playlistEntries,
                podcasts: podcasts, episodes: episodes
            )

    }

    static func snapshot() async throws -> TropLibraryBackupSnapshot {
        try await DatabaseService.shared.read { db in
            try snapshot(in: db)
        }
    }

    /// Only creates bytes in memory. The user explicitly chooses a Files
    /// destination; nothing is uploaded by this service.
    static func export() async throws -> Data {
        let library = try await snapshot()
        return try TropLibraryBackupArchive.encode(library: library)
    }
}
