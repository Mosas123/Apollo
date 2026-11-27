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
    static func podcast(_ id: String) -> String { "spotify:podcast:\(id)" }
    static func audiobook(_ id: String) -> String { "spotify:audiobook:\(id)" }
    static func episode(_ id: String) -> String { "spotify:episode:\(id)" }
    static func chapter(_ id: String) -> String { "spotify:chapter:\(id)" }

    static func isPodcast(_ value: String?) -> Bool {
        value?.hasPrefix("spotify:podcast:") == true
    }

    static func isAudiobook(_ value: String?) -> Bool {
        value?.hasPrefix("spotify:audiobook:") == true
    }

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
        let kind = String(parts[1])
        let pathKind = (kind == "podcast" || kind == "audiobook") ? "show" : kind
        return URL(string: "https://open.spotify.com/\(pathKind)/\(parts[2])")
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
        if !results.podcasts.isEmpty {
            sections.append(SearchSection(title: "Podcasts", items: results.podcasts.map { .podcast(podcast(from: $0)) }))
        }
        if !results.episodes.isEmpty {
            sections.append(SearchSection(title: "Episodes", items: results.episodes.map { .episode(episode(from: $0)) }))
        }
        if !results.audiobooks.isEmpty {
            sections.append(SearchSection(title: "Audiobooks", items: results.audiobooks.map { .album(audiobook(from: $0)) }))
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
            contentKind: .music,
            catalogID: SpotifyCatalogID.track(track.id)
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

    static func podcast(from podcast: CatalogPodcast) -> PodcastItem {
        PodcastItem(
            browseId: SpotifyCatalogID.podcast(podcast.id),
            title: podcast.title,
            author: podcast.author,
            thumbnailUrl: podcast.artworkURL?.absoluteString
        )
    }

    static func episode(from episode: CatalogEpisode) -> EpisodeItem {
        EpisodeItem(
            videoId: SpotifyCatalogID.episode(episode.id),
            title: episode.title,
            artists: episode.showTitle.map { [YTArtist(name: $0)] } ?? [],
            duration: max(0, episode.durationMS / 1000),
            thumbnailUrl: episode.artworkURL?.absoluteString,
            publishDate: episode.releaseDate,
            descriptionText: episode.description,
            viewsText: nil
        )
    }

    static func audiobook(from album: CatalogAlbum) -> AlbumItem {
        AlbumItem(
            browseId: SpotifyCatalogID.audiobook(album.id),
            title: album.title,
            artists: album.artists.map {
                YTArtist(name: $0.name, id: SpotifyCatalogID.artist($0.id))
            },
            year: album.releaseDate.flatMap { Int($0.prefix(4)) },
            thumbnailUrl: album.artworkURL?.absoluteString,
            playlistId: nil,
            isExplicit: false,
            isAudiobook: true
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
