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

    static func preferredImageURL(
        name: String,
        youTubeURL: URL?,
        artistID: String? = nil,
        referenceTracks: [String] = []
    ) async -> URL? {
        // This URL was read from the requested artist's own page. Searching a
        // different catalogue by name must never replace it with a namesake.
        if let youTubeURL, ["https", "http"].contains(youTubeURL.scheme?.lowercased() ?? "") {
            return youTubeURL
        }
        let tracks = Set(referenceTracks.map(TextMatch.normalizeTitle).filter { !$0.isEmpty })
        guard !TextMatch.normalize(name).isEmpty, tracks.count >= 2 else { return nil }
        let key = "verified-v1|\(artistID ?? "")|\(TextMatch.normalize(name))|\(tracks.sorted().joined(separator: "|"))"
        if let cached = await Cache.shared.entry(key) { return cached.url }
        let resolved = await deezerImage(name: name, referenceTracks: tracks)
        guard !Task.isCancelled else { return nil }
        await Cache.shared.store(key, resolved)
        return resolved
    }

    static func avatarImageURL(name: String, youTubeURL: URL?, artistID: String? = nil) async -> URL? {
        await preferredImageURL(name: name, youTubeURL: youTubeURL, artistID: artistID)
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
