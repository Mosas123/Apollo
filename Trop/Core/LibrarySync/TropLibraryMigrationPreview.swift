import Foundation
import GRDB

/// Read-only inventory for migrating from legacy YouTube-owned row IDs to
/// Trop-owned library identities. Never requests provider credentials, never
/// changes existing records and never uploads anything to CloudKit.
struct TropLibraryMigrationPreview: Sendable, Equatable {
    let likedSongs: Int
    let savedAlbums: Int
    let followedArtists: Int
    let savedPlaylists: Int
    let youtubeLinkedPlaylists: Int
    let playlistMemberships: Int
    let followedPodcasts: Int
    let savedEpisodes: Int
    let orphanPlaylistMemberships: Int

    /// A snapshot, not a live CloudKit export. User files and downloaded audio
    /// never enter this inventory or the future metadata-only sync payload.
    static func load() async throws -> TropLibraryMigrationPreview {
        try await DatabaseService.shared.read { db in
            func count(_ query: String) throws -> Int {
                try Int.fetchOne(db, sql: query) ?? 0
            }
            return try TropLibraryMigrationPreview(
                likedSongs: count("SELECT COUNT(*) FROM song WHERE liked = 1"),
                savedAlbums: count("SELECT COUNT(*) FROM album WHERE bookmarked_at IS NOT NULL"),
                followedArtists: count("SELECT COUNT(*) FROM artist WHERE bookmarked_at IS NOT NULL"),
                savedPlaylists: count("SELECT COUNT(*) FROM playlist WHERE bookmarked_at IS NOT NULL"),
                youtubeLinkedPlaylists: count(
                    "SELECT COUNT(*) FROM playlist WHERE bookmarked_at IS NOT NULL AND browse_id IS NOT NULL"
                ),
                playlistMemberships: count("SELECT COUNT(*) FROM playlist_song_map"),
                followedPodcasts: count("SELECT COUNT(*) FROM podcast WHERE subscribed_at IS NOT NULL"),
                savedEpisodes: count("SELECT COUNT(*) FROM episode WHERE saved_at IS NOT NULL"),
                orphanPlaylistMemberships: count(
                    """
                    SELECT COUNT(*) FROM playlist_song_map AS membership
                    LEFT JOIN playlist ON playlist.id = membership.playlist_id
                    LEFT JOIN song ON song.id = membership.song_id
                    WHERE playlist.id IS NULL OR song.id IS NULL
                    """
                )
            )
        }
    }
}
