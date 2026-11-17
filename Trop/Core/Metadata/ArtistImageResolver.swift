import Foundation

/// Resolves artist profile photos from keyless sources.
///
/// Order: Deezer (`picture_xl`, 1000px) → Wikipedia/Wikimedia
/// (`pageimages.original`) → the YouTube Music thumbnail we already have.
enum ArtistImageResolver {
    private actor Cache {
        static let shared = Cache()
        private var hits: [String: URL] = [:]
        private var misses: Set<String> = []

        func hit(_ key: String) -> URL? { hits[key] }
        func isMiss(_ key: String) -> Bool { misses.contains(key) }

        func store(_ key: String, _ url: URL) {
            if hits.count >= 300 { hits.removeAll(keepingCapacity: true) }
            hits[key] = url
        }

        func markMiss(_ key: String) { misses.insert(key) }
    }

    static func preferredImageURL(name: String, youTubeURL: URL?) async -> URL? {
        let key = TextMatch.normalizeArtist(name)
        guard !key.isEmpty else { return youTubeURL }

        if let cached = await Cache.shared.hit(key) { return cached }
        if await Cache.shared.isMiss(key) { return youTubeURL }

        if let deezer = await deezerImage(name: name) {
            await Cache.shared.store(key, deezer)
            return deezer
        }
        if let wiki = await wikipediaImage(name: name) {
            await Cache.shared.store(key, wiki)
            return wiki
        }
        await Cache.shared.markMiss(key)
        return youTubeURL
    }

    /// Lightweight avatar resolution for lists: Deezer 1000px → Wikimedia →
    /// YouTube. Same artist photo as the hero, smaller sizes.
    static func avatarImageURL(name: String, youTubeURL: URL?) async -> URL? {
        let base = TextMatch.normalizeArtist(name)
        guard !base.isEmpty else { return youTubeURL }
        let key = base + "#avatar"
        if let cached = await Cache.shared.hit(key) { return cached }
        if await Cache.shared.isMiss(key) { return youTubeURL }
        if let deezer = await deezerImage(name: name) {
            await Cache.shared.store(key, deezer)
            return deezer
        }
        if let wiki = await wikipediaImage(name: name) {
            await Cache.shared.store(key, wiki)
            return wiki
        }
        await Cache.shared.markMiss(key)
        return youTubeURL
    }

    // MARK: - Deezer

    private struct DeezerArtists: Decodable {
        struct Artist: Decodable {
            let name: String?
            let picture_xl: String?
        }
        let data: [Artist]?
    }

    private static func deezerImage(name: String) async -> URL? {
        var comps = URLComponents(string: "https://api.deezer.com/search/artist")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: TextMatch.queryArtist(name)),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = comps?.url,
              let decoded: DeezerArtists = try? await decode(url) else { return nil }
        let best = decoded.data?.first { TextMatch.artistsMatch($0.name ?? "", name) }
        return best?.picture_xl.flatMap(URL.init(string:))
    }

    // MARK: - Wikipedia / Wikimedia

    private struct WikiQuery: Decodable {
        struct Page: Decodable {
            struct Original: Decodable { let source: String? }
            let original: Original?
        }
        let pages: [String: Page]?
    }

    private static func wikipediaImage(name: String) async -> URL? {
        var comps = URLComponents(string: "https://en.wikipedia.org/w/api.php")
        comps?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: "\(TextMatch.queryArtist(name)) musician"),
            URLQueryItem(name: "gsrlimit", value: "1"),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "original"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*")
        ]
        guard let url = comps?.url,
              let decoded: WikiQuery = try? await decode(url),
              let pages = decoded.pages else { return nil }
        return pages.values
            .compactMap { $0.original?.source }
            .compactMap(URL.init(string:))
            .first
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
