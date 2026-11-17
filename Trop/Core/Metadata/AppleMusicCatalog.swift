import Foundation

/// Keyless Apple Music catalogue client.
///
/// Apple's web player ships a short-lived `AMPWebPlay` developer JWT inside its
/// JS bundle. We harvest it once (plain HTTP, no browser), then call
/// `amp-api.music.apple.com` for search/metadata and 3000px artwork. The token
/// is cached until shortly before it expires and re-harvested on 401.
///
/// This is the same mechanism used by open-source Apple Music scrapers; iTunes
/// Search remains the fallback if harvesting or the API is unavailable.
actor AppleMusicCatalog {
    static let shared = AppleMusicCatalog()

    private let site = "https://music.apple.com"
    private let api = "https://amp-api.music.apple.com"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private var token: String?
    private var tokenExpiry: Date?
    private var harvesting: Task<String?, Never>?

    // MARK: - Public

    /// Resolve canonical metadata + 3000px artwork for a song.
    func songMetadata(title: String, artist: String, storefront: String = "us") async -> ResolvedMetadata? {
        let term = artist.isEmpty ? title : "\(TextMatch.queryArtist(artist)) \(title)"
        guard let url = searchURL(term: term, types: "songs", storefront: storefront),
              let data = await authorizedData(url),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let songs = response.results?.songs?.data else {
            return nil
        }
        let best = songs.first { song in
            guard let attributes = song.attributes, let name = attributes.name else { return false }
            return TextMatch.titlesMatch(name, title)
                && TextMatch.artistsMatch(attributes.artistName ?? "", artist)
        } ?? songs.first { song in
            guard let name = song.attributes?.name else { return false }
            return TextMatch.titlesMatch(name, title)
        }
        guard let attributes = best?.attributes else { return nil }
        return ResolvedMetadata(
            title: attributes.name ?? title,
            artist: attributes.artistName ?? artist,
            album: attributes.albumName,
            year: attributes.releaseDate.flatMap { Int($0.prefix(4)) },
            artworkURL: Self.largeArtwork(attributes.artwork?.url),
            source: "Apple Music"
        )
    }

    /// Album cover by name + artist, at 3000px when available.
    func albumArtwork(album: String, artist: String, storefront: String = "us") async -> URL? {
        let term = artist.isEmpty ? album : "\(TextMatch.queryArtist(artist)) \(album)"
        guard let url = searchURL(term: term, types: "albums", storefront: storefront),
              let data = await authorizedData(url),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let albums = response.results?.albums?.data else {
            return nil
        }
        let best = albums.first { entry in
            guard let name = entry.attributes?.name else { return false }
            return TextMatch.titlesMatch(name, album)
                && TextMatch.artistsMatch(entry.attributes?.artistName ?? "", artist)
        }
        return Self.largeArtwork(best?.attributes?.artwork?.url)
    }

    /// Warm the token in the background (avoids a slow first resolution).
    func warmup() {
        Task { _ = await currentToken(force: false) }
    }

    // MARK: - Token

    private func currentToken(force: Bool) async -> String? {
        if !force, let token, let tokenExpiry, tokenExpiry > Date() {
            return token
        }
        if let harvesting { return await harvesting.value }
        let task = Task<String?, Never> { await harvestToken() }
        harvesting = task
        let harvested = await task.value
        harvesting = nil
        if let harvested {
            token = harvested
            tokenExpiry = Date().addingTimeInterval(6 * 24 * 3600)
        }
        return harvested
    }

    private func harvestToken() async -> String? {
        guard let shell = await fetchText("\(site)/us/404") else { return nil }
        guard let bundlePath = Self.firstGroup(
            in: shell,
            pattern: #"src="(/assets/index~[^"]+\.js)""#
        ) else { return nil }
        guard let bundle = await fetchText(site + bundlePath) else { return nil }
        let pattern = #"eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(bundle.startIndex..., in: bundle)
        for match in regex.matches(in: bundle, range: range) {
            guard let swiftRange = Range(match.range, in: bundle) else { continue }
            let candidate = String(bundle[swiftRange])
            if Self.jwtIssuer(candidate) == "AMPWebPlay" { return candidate }
        }
        return nil
    }

    private func authorizedData(_ url: URL, retried: Bool = false) async -> Data? {
        guard let token = await currentToken(force: false) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(site, forHTTPHeaderField: "Origin")
        request.setValue(site + "/", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401, !retried {
            _ = await currentToken(force: true)
            return await authorizedData(url, retried: true)
        }
        guard (200..<300).contains(http.statusCode) else { return nil }
        return data
    }

    // MARK: - Networking helpers

    private func searchURL(term: String, types: String, storefront: String) -> URL? {
        var components = URLComponents(string: "\(api)/v1/catalog/\(storefront)/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "types", value: types),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "l", value: "en-US")
        ]
        return components?.url
    }

    private func fetchText(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Value helpers

    private static func largeArtwork(_ template: String?) -> URL? {
        guard let template else { return nil }
        let sized = template
            .replacingOccurrences(of: "{w}", with: "3000")
            .replacingOccurrences(of: "{h}", with: "3000")
        return URL(string: sized)
    }

    private static func firstGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func jwtIssuer(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["iss"] as? String
    }

    // MARK: - Response models

    private struct SearchResponse: Decodable {
        let results: Results?
    }

    private struct Results: Decodable {
        let songs: Box?
        let albums: Box?
    }

    private struct Box: Decodable {
        let data: [Entry]?
    }

    private struct Entry: Decodable {
        let attributes: Attributes?
    }

    private struct Attributes: Decodable {
        let name: String?
        let artistName: String?
        let albumName: String?
        let releaseDate: String?
        let artwork: Artwork?
    }

    private struct Artwork: Decodable {
        let url: String?
    }
}
