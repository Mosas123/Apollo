import Foundation

/// IDs that came from the Spotify catalogue use a stable prefix inside the
/// existing UI models. Playback and detail screens can branch on it while the
/// migration is in progress.
enum SpotifyCatalogID {
    static let prefix = "spotify:"

    static func track(_ id: String) -> String { "spotify:track:\(id)" }
    static func album(_ id: String) -> String { "spotify:album:\(id)" }
    static func artist(_ id: String) -> String { "spotify:artist:\(id)" }
    static func playlist(_ id: String) -> String { "spotify:playlist:\(id)" }

    static func isSpotify(_ value: String?) -> Bool {
        value?.hasPrefix(prefix) == true
    }

    static func rawID(_ value: String) -> String? {
        value.split(separator: ":").last.map(String.init)
    }

    static func shareURL(for value: String) -> URL? {
        guard isSpotify(value) else { return nil }
        let parts = value.split(separator: ":")
        guard parts.count >= 3 else { return nil }
        return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
    }
}

/// Projects Spotify catalogue objects into the app's existing UI models so the
/// Home/Search/Detail surfaces keep their current design.
enum SpotifyCatalogMapper {
    static func searchSections(from results: CatalogSearchResults) -> [SearchSection] {
        var sections: [SearchSection] = []

        if !results.tracks.isEmpty {
            sections.append(SearchSection(title: "Songs", items: results.tracks.map { .song(song(from: $0)) }))
        }
        if !results.albums.isEmpty {
            sections.append(SearchSection(title: "Albums", items: results.albums.map { .album(album(from: $0)) }))
        }
        if !results.artists.isEmpty {
            sections.append(SearchSection(title: "Artists", items: results.artists.map { .artist(artist(from: $0)) }))
        }
        if !results.playlists.isEmpty {
            sections.append(SearchSection(title: "Playlists", items: results.playlists.map { .playlist(playlist(from: $0)) }))
        }

        return sections
    }

    static func song(from track: CatalogTrack) -> SongItem {
        SongItem(
            videoId: SpotifyCatalogID.track(track.id),
            title: track.title,
            artists: track.artists.map {
                YTArtist(name: $0.name, id: SpotifyCatalogID.artist($0.id))
            },
            album: track.album?.title,
            albumId: track.album.map { SpotifyCatalogID.album($0.id) },
            duration: max(0, track.durationMS / 1000),
            thumbnailUrl: track.artworkURL?.absoluteString,
            isExplicit: track.isExplicit,
            playlistId: nil,
            viewCount: nil,
            year: nil,
            isVideo: false,
            musicVideoType: nil,
            recordingPreference: .albumAudio,
            contentKind: .music
        )
    }

    static func album(from album: CatalogAlbum) -> AlbumItem {
        AlbumItem(
            browseId: SpotifyCatalogID.album(album.id),
            title: album.title,
            artists: album.artists.map {
                YTArtist(name: $0.name, id: SpotifyCatalogID.artist($0.id))
            },
            year: album.releaseDate.flatMap { Int($0.prefix(4)) },
            thumbnailUrl: album.artworkURL?.absoluteString,
            playlistId: nil,
            isExplicit: false
        )
    }

    static func artist(from artist: CatalogArtist) -> ArtistItem {
        ArtistItem(
            browseId: SpotifyCatalogID.artist(artist.id),
            name: artist.name,
            thumbnailUrl: artist.artworkURL?.absoluteString,
            isSubscribed: false
        )
    }

    static func playlist(from playlist: CatalogPlaylist) -> PlaylistItem {
        PlaylistItem(
            id: SpotifyCatalogID.playlist(playlist.id),
            title: playlist.title,
            author: playlist.owner,
            thumbnailUrl: playlist.artworkURL?.absoluteString,
            songCount: nil
        )
    }
}
