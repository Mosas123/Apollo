import Foundation

/// Profile artwork belongs to an artist identity, not a display name. Preserve
/// the image from that profile; use another catalogue only with track evidence.
enum ArtistImageResolver {
    private actor Cache {
        static let shared = Cache()
        struct Entry: Codable {
            let url: URL?
            let expiresAt: Date
        }
        private var entries: [String: Entry] = [:]
        private let diskURL: URL
        private var saveTask: Task<Void, Never>?

        init() {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            diskURL = base.appendingPathComponent("artist-images.json")
            if let data = try? Data(contentsOf: diskURL),
               let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
                let now = Date()
                entries = decoded.filter { $0.value.expiresAt > now }
            }
        }

        func entry(_ key: String) -> Entry? {
            guard let entry = entries[key], entry.expiresAt > Date() else {
                entries[key] = nil
                return nil
            }
            return entry
        }

        func store(_ key: String, _ url: URL?) {
            if entries.count >= 300 { entries.removeAll(keepingCapacity: true) }
            entries[key] = Entry(url: url, expiresAt: Date().addingTimeInterval(url == nil ? 900 : 86400))
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled,
                      let data = try? JSONEncoder().encode(self.entries) else { return }
                try? data.write(to: self.diskURL, options: .atomic)
            }
        }
    }

    private static let trustedImageHosts = ["scdn.co", "mzstatic.com", "dzcdn.net"]

    static func preferredImageURL(
        name: String,
        youTubeURL: URL?,
        artistID: String? = nil,
        referenceTracks: [String] = []
    ) async -> URL? {
        // Images that already come from a catalogue CDN (Spotify, Apple,
        // Deezer) are authoritative and must not be replaced by a namesake.
        if let youTubeURL, let host = youTubeURL.host?.lowercased(),
           trustedImageHosts.contains(where: { host.hasSuffix($0) }) {
            return youTubeURL
        }

        let normalizedName = TextMatch.normalize(name)
        guard !normalizedName.isEmpty else { return nil }

        let tracks = Set(referenceTracks.map(TextMatch.normalizeTitle).filter { !$0.isEmpty })
        let key = "spotify-first-v1|\(artistID ?? "")|\(normalizedName)|\(tracks.sorted().joined(separator: "|"))"
        if let cached = await Cache.shared.entry(key) { return cached.url }

        if let spotify = await spotifyImage(name: name) {
            guard !Task.isCancelled else { return nil }
            await Cache.shared.store(key, spotify)
            return spotify
        }

        if tracks.count >= 2 {
            let deezer = await deezerImage(name: name, referenceTracks: tracks)
            guard !Task.isCancelled else { return nil }
            await Cache.shared.store(key, deezer)
            return deezer
        }

        await Cache.shared.store(key, nil)
        return nil
    }

    static func avatarImageURL(name: String, youTubeURL: URL?, artistID: String? = nil) async -> URL? {
        await preferredImageURL(name: name, youTubeURL: youTubeURL, artistID: artistID)
    }

    // MARK: - Spotify first

    private static func spotifyImage(name: String) async -> URL? {
        guard let results = try? await SpotifyCatalogProvider().search(name, limit: 6) else {
            return nil
        }
        let wanted = TextMatch.normalize(name)
        return results.artists
            .filter { TextMatch.normalize($0.name) == wanted }
            .compactMap(\.artworkURL)
            .first
    }

    // MARK: - Verified fallback

    private struct DeezerArtists: Decodable {
        struct Artist: Decodable {
            let id: Int
            let name: String?
            let picture_xl: String?
        }
        let data: [Artist]
    }

    private struct DeezerTracks: Decodable {
        struct Track: Decodable {
            struct Artist: Decodable { let id: Int }
            let title: String
            let artist: Artist
        }
        let data: [Track]
    }

    private static func deezerImage(name: String, referenceTracks: Set<String>) async -> URL? {
        var comps = URLComponents(string: "https://api.deezer.com/search/artist")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = comps?.url,
              let decoded: DeezerArtists = try? await decode(url) else { return nil }
        var verified: [URL] = []
        for candidate in decoded.data {
            guard !Task.isCancelled else { return nil }
            guard TextMatch.normalize(candidate.name ?? "") == TextMatch.normalize(name),
                  let image = candidate.picture_xl.flatMap(URL.init(string:)),
                  let tracksURL = URL(string: "https://api.deezer.com/artist/\(candidate.id)/top?limit=50"),
                  let tracks: DeezerTracks = try? await decode(tracksURL) else { continue }
            let catalogueTitles = Set(tracks.data.filter { $0.artist.id == candidate.id }
                .map { TextMatch.normalizeTitle($0.title) })
            // Two distinct recordings must belong to this candidate's numeric
            // artist id. An ambiguous result is not safe to use as a portrait.
            if referenceTracks.intersection(catalogueTitles).count >= 2 {
                verified.append(image)
            }
        }
        return verified.count == 1 ? verified.first : nil
    }

    private static func decode<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
