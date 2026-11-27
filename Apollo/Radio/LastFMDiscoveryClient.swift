import Foundation

struct LastFMTrackMatch: Hashable, Sendable {
    let title: String
    let artist: String
    let match: Double
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
