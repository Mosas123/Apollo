import Foundation

/// Resolves one cover per album (iTunes → Deezer), cached in memory and on
/// disk, so a list of songs from the same album doesn't fire a request per row.
actor AlbumCoverStore {
    static let shared = AlbumCoverStore()

    private var hits: [String: URL] = [:]
    private var misses: Set<String> = []
    private var inflight: [String: Task<URL?, Never>] = [:]
    private let diskURL: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        diskURL = base.appendingPathComponent("album-covers.json")
        if let data = try? Data(contentsOf: diskURL),
           let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in stored {
                if let url = URL(string: value) { hits[key] = url }
            }
        }
    }

    func coverURL(album: String, artist: String) async -> URL? {
        let albumName = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !albumName.isEmpty else { return nil }
        let key = TextMatch.normalizeTitle(albumName) + "|" + TextMatch.normalizeArtist(artist)
        if let hit = hits[key] { return hit }
        if misses.contains(key) { return nil }
        if let task = inflight[key] { return await task.value }

        let task = Task<URL?, Never> { await resolve(album: albumName, artist: artist) }
        inflight[key] = task
        let resolved = await task.value
        inflight[key] = nil
        if let resolved {
            if hits.count >= 500 { hits.removeAll(keepingCapacity: true) }
            hits[key] = resolved
            persist()
        } else {
            misses.insert(key)
        }
        return resolved
    }

    private func resolve(album: String, artist: String) async -> URL? {
        if let itunes = await iTunesAlbum(album: album, artist: artist) { return itunes }
        return await deezerAlbum(album: album, artist: artist)
    }

    // MARK: - iTunes

    private struct ITunesAlbums: Decodable {
        struct Album: Decodable {
            let collectionName: String?
            let artistName: String?
            let artworkUrl100: String?
        }
        let results: [Album]?
    }

    private func iTunesAlbum(album: String, artist: String) async -> URL? {
        var comps = URLComponents(string: "https://itunes.apple.com/search")
        let query = artist.isEmpty ? album : "\(TextMatch.queryArtist(artist)) \(album)"
        comps?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = comps?.url,
              let decoded: ITunesAlbums = try? await decode(url) else { return nil }
        let candidates = (decoded.results ?? []).filter { entry in
            guard let name = entry.collectionName else { return false }
            return TextMatch.albumsMatch(name, album)
                && (artist.isEmpty || TextMatch.artistsMatch(entry.artistName ?? "", artist))
        }
        guard let artwork = candidates.first?.artworkUrl100 else { return nil }
        let sized = artwork
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100", with: "600x600")
        return URL(string: sized)
    }

    // MARK: - Deezer

    private struct DeezerAlbums: Decodable {
        struct Album: Decodable {
            struct Artist: Decodable { let name: String? }
            let title: String?
            let artist: Artist?
            let cover_big: String?
        }
        let data: [Album]?
    }

    private func deezerAlbum(album: String, artist: String) async -> URL? {
        var comps = URLComponents(string: "https://api.deezer.com/search/album")
        let query = artist.isEmpty ? album : "\(TextMatch.queryArtist(artist)) \(album)"
        comps?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = comps?.url,
              let decoded: DeezerAlbums = try? await decode(url) else { return nil }
        let candidates = (decoded.data ?? []).filter { entry in
            guard let name = entry.title else { return false }
            return TextMatch.albumsMatch(name, album)
                && (artist.isEmpty || TextMatch.artistsMatch(entry.artist?.name ?? "", artist))
        }
        return candidates.first?.cover_big.flatMap(URL.init(string:))
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func clear() {
        hits.removeAll()
        misses.removeAll()
        try? FileManager.default.removeItem(at: diskURL)
    }

    private func persist() {
        let snapshot = hits.reduce(into: [String: String]()) { result, entry in
            result[entry.key] = entry.value.absoluteString
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: diskURL, options: .atomic)
    }
}
