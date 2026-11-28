import Foundation

/// One artwork subject shared by rows, cards, headers and the player. The
/// resolver always returns a catalogue-sized image (Apple/Deezer 1000–1200)
/// when the recording can be matched, independent of the audio carrier.
enum ArtworkSubject: Hashable, Sendable {
    case track(title: String, artist: String, album: String?, duration: Int?)
    case album(title: String, artist: String)
    case artist(name: String, spotifyID: String?)
    case podcast(show: String)

    var cacheKey: String {
        switch self {
        case .track(let title, let artist, let album, let duration):
            return "track|\(TextMatch.normalizeTitle(title))|\(TextMatch.normalizeArtist(artist))|\(TextMatch.normalize(album ?? ""))|\(duration ?? 0)"
        case .album(let title, let artist):
            return "album|\(TextMatch.normalizeTitle(title))|\(TextMatch.normalizeArtist(artist))"
        case .artist(let name, let spotifyID):
            return "artist|\(TextMatch.normalizeArtist(name))|\(spotifyID ?? "")"
        case .podcast(let show):
            return "podcast|\(show.lowercased())"
        }
    }
}

actor ArtworkURLCache {
    static let shared = ArtworkURLCache()
    private struct Entry { let url: URL?; let expiresAt: Date }
    private var entries: [String: Entry] = [:]
    private let positiveTTL: TimeInterval = 24 * 60 * 60
    private let negativeTTL: TimeInterval = 15 * 60

    func lookup(_ key: String) -> (found: Bool, url: URL?) {
        guard let entry = entries[key], entry.expiresAt > Date() else {
            entries[key] = nil
            return (false, nil)
        }
        return (true, entry.url)
    }

    func store(_ url: URL?, for key: String) {
        let ttl = url == nil ? negativeTTL : positiveTTL
        entries[key] = Entry(url: url, expiresAt: Date().addingTimeInterval(ttl))
    }
}

enum ArtworkResolver {
    static func upgrade(_ subject: ArtworkSubject) async -> URL? {
        let key = subject.cacheKey
        let cached = await ArtworkURLCache.shared.lookup(key)
        if cached.found { return cached.url }

        let url: URL?
        switch subject {
        case .track(let title, let artist, let album, let duration):
            url = await trackURL(title: title, artist: artist, album: album, duration: duration)
        case .album(let title, let artist):
            url = await MetadataResolver.albumArtwork(title: title, artist: artist)
        case .artist(let name, let spotifyID):
            url = await artistURL(name: name, spotifyID: spotifyID)
        case .podcast(let show):
            url = await PodcastAudioResolver.shared.artwork(for: show)
        }
        await ArtworkURLCache.shared.store(url, for: key)
        return url
    }

    static func trackURL(
        title: String,
        artist: String,
        album: String?,
        duration: Int?
    ) async -> URL? {
        let query = TextMatch.recordingQuery(title: title, artist: artist)
        guard !query.title.isEmpty else { return nil }

        let resolved = await MetadataResolver.enrich(
            title: query.title,
            artist: query.artist,
            album: album,
            duration: duration
        )
        // The cover belongs to the recording, not to the album edition. A
        // deluxe/single name difference must not throw away the 1200 px image.
        var url = resolved.flatMap { candidate -> URL? in
            guard TextMatch.recordingsMatch(candidate.title, query.title),
                  TextMatch.artistsMatch(candidate.artist, query.artist) else { return nil }
            return candidate.artworkURL
        }
        if url == nil, let album, !album.isEmpty {
            url = await MetadataResolver.albumArtwork(title: album, artist: query.artist)
        }
        return highRes(url)
    }

    static func artistURL(name: String, spotifyID: String?) async -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let wanted = TextMatch.normalizeArtist(trimmed)
        if let items = try? await AppleCatalogClient().search(
            term: trimmed,
            entity: .musicArtist,
            limit: 5
        ), let match = items.first(where: {
            TextMatch.normalizeArtist($0.artistName ?? $0.title) == wanted
        }), let artwork = match.artworkURL {
            return highRes(artwork)
        }
        if let spotifyID,
           let resolved = await ArtistImageResolver.preferredImageURL(
               name: trimmed,
               youTubeURL: nil,
               artistID: spotifyID,
               referenceTracks: []
           ) {
            return highRes(resolved)
        }
        return nil
    }

    private static func highRes(_ url: URL?) -> URL? {
        ArtworkURLs.highRes(url?.absoluteString).flatMap(URL.init(string:))
    }
}
