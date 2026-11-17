import Foundation

/// Resolves artist profile photos from keyless sources, since the YouTube
/// Music catalogue is currently the only one feeding them.
///
/// Order: Deezer (`picture_xl`, 1000px) → Wikipedia/Wikimedia
/// (`pageimages.original`) → the YouTube thumbnail we already have.
enum ArtistImageResolver {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var hits: [String: URL] = [:]
    nonisolated(unsafe) private static var misses: Set<String> = []

    static func preferredImageURL(name: String, youTubeURL: URL?) async -> URL? {
        let key = normalize(name)
        guard !key.isEmpty else { return youTubeURL }

        lock.lock()
        if let cached = hits[key] { lock.unlock(); return cached }
        if misses.contains(key) { lock.unlock(); return youTubeURL }
        lock.unlock()

        if let deezer = await deezerImage(name: name) {
            store(key, deezer)
            return deezer
        }
        if let wiki = await wikipediaImage(name: name) {
            store(key, wiki)
            return wiki
        }
        lock.lock(); misses.insert(key); lock.unlock()
        return youTubeURL
    }

    private static func store(_ key: String, _ url: URL) {
        lock.lock()
        if hits.count >= 300 { hits.removeAll(keepingCapacity: true) }
        hits[key] = url
        lock.unlock()
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
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = comps?.url,
              let decoded: DeezerArtists = try? await decode(url) else { return nil }
        let target = normalize(name)
        let best = decoded.data?.first { normalize($0.name ?? "") == target } ?? decoded.data?.first
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
            URLQueryItem(name: "gsrsearch", value: "\(name) musician"),
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

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }
}
