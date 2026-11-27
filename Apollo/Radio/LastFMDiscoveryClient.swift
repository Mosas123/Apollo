import Foundation

struct LastFMTrackMatch: Hashable, Sendable {
    let title: String
    let artist: String
    let match: Double
}

struct LastFMArtistMatch: Hashable, Sendable {
    let name: String
    let match: Double
}

struct LastFMTagMatch: Hashable, Sendable {
    let name: String
    let count: Int
}

actor LastFMArtistCache {
    static let shared = LastFMArtistCache()
    private struct Entry { let artists: [LastFMArtistMatch]; let at: Date }
    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 24 * 60 * 60

    func artists(for key: String) -> [LastFMArtistMatch]? {
        guard let entry = entries[key], Date().timeIntervalSince(entry.at) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.artists
    }

    func store(_ artists: [LastFMArtistMatch], for key: String) {
        entries[key] = Entry(artists: artists, at: Date())
    }
}

actor LastFMTagCache {
    static let shared = LastFMTagCache()
    private struct Entry { let tags: [LastFMTagMatch]; let at: Date }
    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 24 * 60 * 60

    func tags(for key: String) -> [LastFMTagMatch]? {
        guard let entry = entries[key], Date().timeIntervalSince(entry.at) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.tags
    }

    func store(_ tags: [LastFMTagMatch], for key: String) {
        entries[key] = Entry(tags: tags, at: Date())
    }
}

actor LastFMDiscoveryCache {
    static let shared = LastFMDiscoveryCache()
    private struct Entry { let tracks: [LastFMTrackMatch]; let at: Date }
    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 24 * 60 * 60

    func tracks(for key: String) -> [LastFMTrackMatch]? {
        guard let entry = entries[key], Date().timeIntervalSince(entry.at) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.tracks
    }

    func store(_ tracks: [LastFMTrackMatch], for key: String) {
        entries[key] = Entry(tracks: tracks, at: Date())
    }
}

/// Read-only Last.fm similarity. It only needs the public API key, never the
/// user's session, and it never supplies audio.
struct LastFMDiscoveryClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func similarTracks(title: String, artist: String, limit: Int = 12) async -> [LastFMTrackMatch] {
        let apiKey = LastFMDefaults.apiKey
        guard !apiKey.isEmpty, !title.isEmpty, !artist.isEmpty else { return [] }

        let key = "\(title.lowercased())|\(artist.lowercased())|\(limit)"
        if let cached = await LastFMDiscoveryCache.shared.tracks(for: key) {
            return cached
        }

        var components = URLComponents(string: LastFMDefaults.baseUrl)
        components?.queryItems = [
            URLQueryItem(name: "method", value: "track.getSimilar"),
            URLQueryItem(name: "track", value: title),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "autocorrect", value: "1"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 30)))),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            return []
        }

        let matches = (decoded.similarTracks?.tracks ?? []).compactMap { track -> LastFMTrackMatch? in
            guard let artist = track.artist?.name, !artist.isEmpty, !track.name.isEmpty else { return nil }
            return LastFMTrackMatch(
                title: track.name,
                artist: artist,
                match: Double(track.match ?? "0") ?? 0
            )
        }

        await LastFMDiscoveryCache.shared.store(matches, for: key)
        return matches
    }

    func topTags(artist: String, limit: Int = 8) async -> [LastFMTagMatch] {
        let apiKey = LastFMDefaults.apiKey
        guard !apiKey.isEmpty, !artist.isEmpty else { return [] }

        let key = "\(artist.lowercased())|\(limit)"
        if let cached = await LastFMTagCache.shared.tags(for: key) {
            return cached
        }

        var components = URLComponents(string: LastFMDefaults.baseUrl)
        components?.queryItems = [
            URLQueryItem(name: "method", value: "artist.getTopTags"),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "autocorrect", value: "1"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(TagResponse.self, from: data) else {
            return []
        }

        let tags = (decoded.topTags?.tags ?? []).compactMap { tag -> LastFMTagMatch? in
            let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let lower = name.lowercased()
            let ignored = ["seen live", "favorite", "favourites", "spotify", "owned", "albums i own", "under 2000 listeners"]
            guard !ignored.contains(lower) else { return nil }
            guard lower != artist.lowercased() else { return nil }
            return LastFMTagMatch(name: name, count: Int(tag.count ?? "0") ?? 0)
        }.sorted { $0.count > $1.count }

        let result = Array(tags.prefix(max(1, limit)))
        await LastFMTagCache.shared.store(result, for: key)
        return result
    }

    func similarArtists(name: String, limit: Int = 10) async -> [LastFMArtistMatch] {
        let apiKey = LastFMDefaults.apiKey
        guard !apiKey.isEmpty, !name.isEmpty else { return [] }

        let key = "\(name.lowercased())|\(limit)"
        if let cached = await LastFMArtistCache.shared.artists(for: key) {
            return cached
        }

        var components = URLComponents(string: LastFMDefaults.baseUrl)
        components?.queryItems = [
            URLQueryItem(name: "method", value: "artist.getSimilar"),
            URLQueryItem(name: "artist", value: name),
            URLQueryItem(name: "autocorrect", value: "1"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 30)))),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ArtistResponse.self, from: data) else {
            return []
        }

        let matches = (decoded.similarArtists?.artists ?? []).compactMap { artist -> LastFMArtistMatch? in
            guard !artist.name.isEmpty else { return nil }
            return LastFMArtistMatch(
                name: artist.name,
                match: Double(artist.match ?? "0") ?? 0
            )
        }

        await LastFMArtistCache.shared.store(matches, for: key)
        return matches
    }

    private struct TagResponse: Decodable {
        let topTags: Container?
        enum CodingKeys: String, CodingKey {
            case topTags = "toptags"
        }
        struct Container: Decodable {
            let tags: [Tag]
            enum CodingKeys: String, CodingKey { case tags = "tag" }
        }
        struct Tag: Decodable {
            let name: String
            let count: String?
        }
    }

    private struct ArtistResponse: Decodable {
        let similarArtists: Container?
        enum CodingKeys: String, CodingKey {
            case similarArtists = "similarartists"
        }
        struct Container: Decodable {
            let artists: [Artist]
            enum CodingKeys: String, CodingKey { case artists = "artist" }
        }
        struct Artist: Decodable {
            let name: String
            let match: String?
        }
    }

    private struct Response: Decodable {
        let similarTracks: Container?
        enum CodingKeys: String, CodingKey {
            case similarTracks = "similartracks"
        }
        struct Container: Decodable {
            let tracks: [Track]
            enum CodingKeys: String, CodingKey { case tracks = "track" }
        }
        struct Track: Decodable {
            let name: String
            let match: String?
            let artist: Artist?
        }
        struct Artist: Decodable {
            let name: String
        }
    }
}
