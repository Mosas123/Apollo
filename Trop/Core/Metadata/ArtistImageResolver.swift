import Foundation

/// Resolves artist profile photos from keyless sources, since the YouTube
/// Music catalogue is currently the only one feeding them.
///
/// Order: Apple Music artist page (`AMBArtistImages`, up to 2400px, keyless —
/// the public web page exposes the image in `og:image`) → Deezer
/// (`picture_xl`, 1000px) → Wikipedia/Wikimedia (`pageimages.original`) → the
/// YouTube thumbnail we already have.
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
        let key = normalize(name)
        guard !key.isEmpty else { return youTubeURL }

        if let cached = await Cache.shared.hit(key) { return cached }
        if await Cache.shared.isMiss(key) { return youTubeURL }

        if let apple = await appleMusicImage(name: name) {
            await Cache.shared.store(key, apple)
            return apple
        }
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

    // MARK: - Apple Music (web page, keyless)

    private struct ITunesArtists: Decodable {
        struct Artist: Decodable {
            let artistName: String?
            let artistId: Int?
        }
        let results: [Artist]?
    }

    /// Finds the artist on iTunes, opens their public Apple Music page, and
    /// rewrites the `AMBArtistImages` URL to a large square crop. No developer
    /// token is involved — this is the same image the website shows.
    private static func appleMusicImage(name: String) async -> URL? {
        var search = URLComponents(string: "https://itunes.apple.com/search")
        search?.queryItems = [
            URLQueryItem(name: "term", value: name),
            URLQueryItem(name: "entity", value: "musicArtist"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let searchURL = search?.url,
              let artists: ITunesArtists = try? await decode(searchURL) else { return nil }
        let target = normalize(name)
        let match = artists.results?.first { normalize($0.artistName ?? "") == target }
            ?? artists.results?.first { artist in
                let other = normalize(artist.artistName ?? "")
                return !other.isEmpty && (other.contains(target) || target.contains(other))
            }
        guard let artistId = match?.artistId else { return nil }

        var pageRequest = URLRequest(url: URL(string: "https://music.apple.com/us/artist/\(artistId)")!)
        pageRequest.timeoutInterval = 15
        pageRequest.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, response) = try? await URLSession.shared.data(for: pageRequest),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { return nil }
        return appleImageURL(fromHTML: html)
    }

    static func appleImageURL(fromHTML html: String) -> URL? {
        // Greedy so it captures the full URL including the trailing
        // `/1200x630cw.png` transform segment, not the base filename.
        let pattern = #"https://is\d+-ssl\.mzstatic\.com/image/thumb/AMCArtistImages[^"']+\.(?:png|jpg|jpeg|webp)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else { return nil }
        let original = String(html[range])
        // Replace the trailing /WxHcc… suffix with a large square crop.
        let rewrite = #"/\d+x\d+[a-zA-Z-]*(?:-\d+)?\.(?:webp|jpg|jpeg|png)$"#
        guard let sizeRegex = try? NSRegularExpression(pattern: rewrite, options: .caseInsensitive) else {
            return URL(string: original)
        }
        let full = NSRange(original.startIndex..., in: original)
        let sized = sizeRegex.stringByReplacingMatches(
            in: original, range: full, withTemplate: "/1800x1800cc-100.jpg"
        )
        return URL(string: sized)
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
