import Foundation

@main
enum TropLibraryBackupArchiveChecks {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = TropLibraryBackupSnapshot(
            tracks: [
                .init(
                    id: "video-one", title: "Example", artistName: "An artist",
                    albumName: "Album", duration: 180, liked: true,
                    inLibrary: now, isEpisode: false, createdAt: now
                )
            ],
            albums: [.init(id: "album-1", title: "Album", bookmarkedAt: now)],
            artists: [.init(id: "artist-1", name: "An artist", bookmarkedAt: now)],
            playlists: [.init(
                id: "playlist-1", name: "Favorites", browseId: "VLPL-legacy",
                bookmarkedAt: now, isEditable: false
            )],
            playlistEntries: [
                .init(playlistId: "playlist-1", songId: "video-one", position: 0),
                // Preserve repeated occurrences rather than deduplicating.
                .init(playlistId: "playlist-1", songId: "video-one", position: 1)
            ],
            podcasts: [.init(id: "podcast-1", name: "A show", subscribedAt: now)],
            episodes: [.init(
                id: "episode-1", title: "An episode", podcastId: "podcast-1",
                duration: 2_000, isPlayed: false, savedAt: now
            )]
        )

        let data = try TropLibraryBackupArchive.encode(library: snapshot, createdAt: now)
        let decoded = try TropLibraryBackupArchive.decode(data)
        assert(decoded.library == snapshot)
        let summary = try TropLibraryBackupArchive.inspect(data)
        assert(summary.likedSongs == 1)
        assert(summary.playlists == 1)
        assert(summary.playlistEntries == 2)
        assert(summary.unresolvedEntries == 0)
        assert(summary.episodes == 1)

        let text = String(decoding: data, as: UTF8.self)
        assert(!text.contains("library_add_token"))
        assert(!text.contains("library_remove_token"))
        assert(!text.contains("downloaded_track"))
        assert(!text.contains("local_path"))
        assert(!text.contains("playback_url"))
        assert(!text.contains("thumbnail_url"))

        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var library = json["library"] as! [String: Any]
        var tracks = library["tracks"] as! [[String: Any]]
        tracks[0]["liked"] = false
        library["tracks"] = tracks
        json["library"] = library
        let tampered = try JSONSerialization.data(withJSONObject: json)
        do {
            _ = try TropLibraryBackupArchive.decode(tampered)
            fatalError("Modified backup must fail SHA-256 validation")
        } catch TropLibraryBackupError.checksumMismatch {
            // Expected.
        }

        json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["schemaVersion"] = 9_999
        do {
            _ = try TropLibraryBackupArchive.decode(
                JSONSerialization.data(withJSONObject: json)
            )
            fatalError("Future schema must not be restored silently")
        } catch TropLibraryBackupError.unsupportedFormat {
            // Expected.
        }

        let unsafe = TropLibraryBackupSnapshot(
            tracks: [.init(
                id: "https://example.com/token?secret=1", title: "Unsafe",
                artistName: nil, albumName: nil, duration: 0, liked: true,
                inLibrary: nil, isEpisode: false, createdAt: now
            )],
            albums: [], artists: [], playlists: [],
            playlistEntries: [], podcasts: [], episodes: []
        )
        do {
            _ = try TropLibraryBackupArchive.encode(library: unsafe)
            fatalError("Never export a signed URL or credential-like source ID")
        } catch TropLibraryBackupError.invalidPayload {
            // Expected.
        }

        let orphanSnapshot = TropLibraryBackupSnapshot(
            tracks: snapshot.tracks,
            albums: snapshot.albums,
            artists: snapshot.artists,
            playlists: snapshot.playlists,
            playlistEntries: [.init(
                playlistId: "playlist-1", songId: "orphan-song", position: 4
            )],
            podcasts: snapshot.podcasts,
            episodes: snapshot.episodes
        )
        let orphan = try TropLibraryBackupArchive.inspect(
            TropLibraryBackupArchive.encode(library: orphanSnapshot, createdAt: now)
        )
        assert(orphan.unresolvedEntries == 1)
        print("Trop portable backup archive checks passed")
    }
}
