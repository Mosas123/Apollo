import Foundation

/// Canonical metadata resolved from an external catalogue.
struct ResolvedMetadata: Sendable {
    let title: String
    let artist: String
    let album: String?
    let year: Int?
    let artworkURL: URL?
    let source: String
}

/// Multi-source metadata enrichment with fallback: iTunes Search (fast, free,
/// no auth) first, then MusicBrainz + Cover Art Archive. Never uploads anything;
/// only reads public catalogues.
enum MetadataResolver {
    /// Resolve canonical metadata for a track. Tries iTunes, then MusicBrainz.
    static func enrich(title: String, artist: String, album: String? = nil) async -> ResolvedMetadata? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let key = cacheKey(title: title, artist: artist)
        if let cached = await MetadataCache.shared.lookup(key) {
            return cached.value
        }

        var resolved = await iTunes(title: title, artist: artist, album: album)
        if resolved == nil {
            resolved = await musicBrainz(title: title, artist: artist)
        }
        await MetadataCache.shared.store(key, resolved)
        return resolved
    }

    private static func cacheKey(title: String, artist: String) -> String {
        "\(normalize(title))|\(normalize(artist))"
    }

    // MARK: - iTunes Search

    private struct ITunesResponse: Decodable {
        struct Result: Decodable {
            let trackName: String?
            let artistName: String?
            let collectionName: String?
            let releaseDate: String?
            let artworkUrl100: String?
        }
        let results: [Result]
    }

    private static func iTunes(title: String, artist: String, album: String?) async -> ResolvedMetadata? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components?.url,
              let response: ITunesResponse = try? await decode(url, headers: [:]) else {
            return nil
        }

        let targetTitle = normalize(title)
        let targetArtist = normalize(artist)
        let best = response.results.first { result in
            guard let track = result.trackName, let name = result.artistName else { return false }
            let titleMatches = normalize(track).contains(targetTitle) || targetTitle.contains(normalize(track))
            let artistMatches = targetArtist.isEmpty
                || normalize(name).contains(targetArtist)
                || targetArtist.contains(normalize(name))
            return titleMatches && artistMatches
        }
        guard let best else { return nil }

        let artwork = best.artworkUrl100?
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100", with: "600x600")
        let year = best.releaseDate.flatMap { Int($0.prefix(4)) }
        return ResolvedMetadata(
            title: best.trackName ?? title,
            artist: best.artistName ?? artist,
            album: best.collectionName ?? album,
            year: year,
            artworkURL: artwork.flatMap(URL.init(string:)),
            source: "iTunes"
        )
    }

    // MARK: - MusicBrainz + Cover Art Archive

    private struct MusicBrainzResponse: Decodable {
        struct Recording: Decodable {
            struct Release: Decodable {
                let id: String
                let title: String?
                let date: String?
            }
            let title: String?
            let firstReleaseDate: String?
            let releases: [Release]?
        }
        let recordings: [Recording]
    }

    private static func musicBrainz(title: String, artist: String) async -> ResolvedMetadata? {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording/")
        components?.queryItems = [
            URLQueryItem(name: "query", value: "recording:\"\(title)\" AND artist:\"\(artist)\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "1")
        ]
        // MusicBrainz requires an identifying User-Agent.
        let headers = ["User-Agent": "Thrum/1.0 (https://github.com/Mosas123/Trop)"]
        guard let url = components?.url,
              let response: MusicBrainzResponse = try? await decode(url, headers: headers),
              let recording = response.recordings.first else {
            return nil
        }

        let release = recording.releases?.first
        let year = (release?.date ?? recording.firstReleaseDate).flatMap { Int($0.prefix(4)) }
        var artworkURL: URL?
        if let releaseID = release?.id {
            artworkURL = URL(string: "https://coverartarchive.org/release/\(releaseID)/front-500")
        }
        return ResolvedMetadata(
            title: recording.title ?? title,
            artist: artist,
            album: release?.title,
            year: year,
            artworkURL: artworkURL,
            source: "MusicBrainz"
        )
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ url: URL, headers: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Small in-memory cache (positive and negative) so repeated tracks don't refetch.
actor MetadataCache {
    static let shared = MetadataCache()

    struct Entry: Sendable {
        let value: ResolvedMetadata?
    }

    private var store: [String: Entry] = [:]

    func lookup(_ key: String) -> Entry? {
        store[key]
    }

    func store(_ key: String, _ value: ResolvedMetadata?) {
        store[key] = Entry(value: value)
    }
}
