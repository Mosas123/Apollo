import Foundation

/// Fields that another catalogue can contribute without replacing the primary
/// record. The primary (Spotify) track is only extended, never rewritten.
struct CatalogEnrichment: Sendable {
    var artworkURL: URL?
    var artworkSource: CatalogSource?
    var genre: String?
    var genreSource: CatalogSource?
    var releaseDate: String?
    var releaseDateSource: CatalogSource?
    var isrc: String?
    var mbid: String?
}

extension CatalogEnrichment {
    func merged(with other: CatalogEnrichment) -> CatalogEnrichment {
        CatalogEnrichment(
            artworkURL: artworkURL ?? other.artworkURL,
            artworkSource: artworkURL != nil ? artworkSource : other.artworkSource,
            genre: genre ?? other.genre,
            genreSource: genre != nil ? genreSource : other.genreSource,
            releaseDate: releaseDate ?? other.releaseDate,
            releaseDateSource: releaseDate != nil ? releaseDateSource : other.releaseDateSource,
            isrc: isrc ?? other.isrc,
            mbid: mbid ?? other.mbid
        )
    }
}

extension CatalogTrack {
    func applying(_ enrichment: CatalogEnrichment) -> CatalogTrack {
        CatalogTrack(
            id: id,
            source: source,
            title: title,
            artists: artists,
            album: album,
            durationMS: durationMS,
            isrc: isrc ?? enrichment.isrc,
            artworkURL: artworkURL ?? enrichment.artworkURL,
            externalURL: externalURL,
            isExplicit: isExplicit
        )
    }
}

extension CatalogAlbum {
    func applying(_ enrichment: CatalogEnrichment) -> CatalogAlbum {
        CatalogAlbum(
            id: id,
            source: source,
            title: title,
            artists: artists,
            releaseDate: releaseDate ?? enrichment.releaseDate,
            artworkURL: artworkURL ?? enrichment.artworkURL,
            externalURL: externalURL
        )
    }
}

/// Field-level enrichment. Apple/iTunes contributes artwork, genre and date;
/// it never touches artists, playback or the primary identifiers.
struct CatalogEnricher: Sendable {
    private let apple = AppleCatalogClient()
    private let musicBrainz = MusicBrainzClient()

    func enrich(_ track: CatalogTrack) async -> CatalogEnrichment {
        var enrichment = CatalogEnrichment()
        let artist = track.artists.first?.name ?? ""

        if track.artworkURL == nil {
            let term = [track.title, artist].filter { !$0.isEmpty }.joined(separator: " ")
            let matches = (try? await apple.search(term: term, entity: .song, limit: 5)) ?? []
            if let match = bestTrackMatch(track, in: matches) {
                enrichment.artworkURL = match.artworkURL
                enrichment.artworkSource = match.artworkURL == nil ? nil : .apple
                enrichment.genre = match.genre
                enrichment.genreSource = match.genre == nil ? nil : .apple
                enrichment.releaseDate = match.releaseDate
                enrichment.releaseDateSource = match.releaseDate == nil ? nil : .apple
            }
        }

        if track.isrc == nil {
            let recording = try? await musicBrainz.lookup(
                title: track.title,
                artist: artist,
                durationMS: track.durationMS
            )
            if let recording {
                enrichment.isrc = recording.isrcs.first
                enrichment.mbid = recording.id
                if enrichment.releaseDate == nil, let date = recording.releaseDate {
                    enrichment.releaseDate = date
                    enrichment.releaseDateSource = .musicBrainz
                }
            }
        }

        return enrichment
    }

    func enrich(_ album: CatalogAlbum) async -> CatalogEnrichment {
        guard album.artworkURL == nil || album.releaseDate == nil else { return CatalogEnrichment() }

        let artist = album.artists.first?.name ?? ""
        let term = [album.title, artist].filter { !$0.isEmpty }.joined(separator: " ")
        let matches = (try? await apple.search(term: term, entity: .album, limit: 5)) ?? []
        guard let match = bestAlbumMatch(album, in: matches) else { return CatalogEnrichment() }

        return CatalogEnrichment(
            artworkURL: album.artworkURL == nil ? match.artworkURL : nil,
            artworkSource: album.artworkURL == nil ? .apple : nil,
            genre: match.genre,
            genreSource: match.genre == nil ? nil : .apple,
            releaseDate: album.releaseDate == nil ? match.releaseDate : nil,
            releaseDateSource: album.releaseDate == nil && match.releaseDate != nil ? .apple : nil
        )
    }

    private func bestTrackMatch(_ track: CatalogTrack, in items: [AppleCatalogItem]) -> AppleCatalogItem? {
        let wantedTitle = TextMatch.normalizeTitle(track.title)
        let wantedArtist = track.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""

        return items.first { item in
            let title = TextMatch.normalizeTitle(item.title)
            guard !wantedTitle.isEmpty, title == wantedTitle || title.contains(wantedTitle) else {
                return false
            }
            if !wantedArtist.isEmpty, let artist = item.artistName {
                let normalized = TextMatch.normalizeArtist(artist)
                guard normalized == wantedArtist || normalized.contains(wantedArtist) else { return false }
            }
            if track.durationMS > 0, let duration = item.durationMS, duration > 0 {
                guard abs(duration - track.durationMS) <= 20_000 else { return false }
            }
            return true
        }
    }

    private func bestAlbumMatch(_ album: CatalogAlbum, in items: [AppleCatalogItem]) -> AppleCatalogItem? {
        let wantedTitle = TextMatch.normalizeTitle(album.title)
        let wantedArtist = album.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""

        return items.first { item in
            let title = TextMatch.normalizeTitle(item.collectionName ?? item.title)
            guard !wantedTitle.isEmpty, title == wantedTitle || title.contains(wantedTitle) else {
                return false
            }
            if !wantedArtist.isEmpty, let artist = item.artistName {
                let normalized = TextMatch.normalizeArtist(artist)
                guard normalized == wantedArtist || normalized.contains(wantedArtist) else { return false }
            }
            return true
        }
    }
}
