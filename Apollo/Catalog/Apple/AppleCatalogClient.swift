import Foundation

/// iTunes/Apple catalogue lookup used only to enrich fields Spotify may omit:
/// high-resolution artwork, genre and release date. It never provides audio and
/// never replaces Spotify's artist list.
enum AppleCatalogEntity: String, Sendable {
    case song
    case album
    case musicArtist
}

struct AppleCatalogItem: Identifiable, Hashable, Sendable {
    let id: Int
    let entity: String
    let title: String
    let artistName: String?
    let collectionName: String?
    let artworkURL: URL?
    let genre: String?
    let releaseDate: String?
    let durationMS: Int?
}

enum AppleCatalogError: Error, Sendable {
    case invalidResponse
    case http(Int)
}

actor AppleCatalogCache {
    static let shared = AppleCatalogCache()

    private struct Entry {
        let items: [AppleCatalogItem]
        let at: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 6 * 60 * 60
    private let maxEntries = 256

    func items(for key: String) -> [AppleCatalogItem]? {
        guard let entry = entries[key] else { return nil }
        guard Date().timeIntervalSince(entry.at) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.items
    }

    func store(_ items: [AppleCatalogItem], for key: String) {
        if entries.count >= maxEntries {
            let cutoff = Date().addingTimeInterval(-ttl)
            entries = entries.filter { $0.value.at >= cutoff }
            if entries.count >= maxEntries { entries.removeAll(keepingCapacity: true) }
        }
        entries[key] = Entry(items: items, at: Date())
    }
}

struct AppleCatalogClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        term: String,
        entity: AppleCatalogEntity = .song,
        limit: Int = 10,
        country: String = "US"
    ) async throws -> [AppleCatalogItem] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let key = "\(entity.rawValue)|\(country)|\(limit)|\(trimmed.lowercased())"
        if let cached = await AppleCatalogCache.shared.items(for: key) {
            return cached
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: entity.rawValue),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 50)))),
            URLQueryItem(name: "country", value: country)
        ]

        guard let url = components?.url else { throw AppleCatalogError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppleCatalogError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppleCatalogError.http(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let items = decoded.results.compactMap { result -> AppleCatalogItem? in
            let title = result.trackName ?? result.collectionName ?? result.artistName
            guard let title, !title.isEmpty else { return nil }
            let id = result.trackId ?? result.collectionId ?? result.artistId ?? 0
            guard id != 0 else { return nil }
            return AppleCatalogItem(
                id: id,
                entity: result.wrapperType ?? entity.rawValue,
                title: title,
                artistName: result.artistName,
                collectionName: result.collectionName,
                artworkURL: Self.upscaledArtwork(result.artworkUrl100),
                genre: result.primaryGenreName,
                releaseDate: result.releaseDate,
                durationMS: result.trackTimeMillis
            )
        }

        await AppleCatalogCache.shared.store(items, for: key)
        return items
    }

    /// iTunes serves 100×100 by default; the same asset exists at larger sizes.
    private static func upscaledArtwork(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        let scaled = value
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100", with: "600x600")
        return URL(string: scaled)
    }

    private struct Response: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let wrapperType: String?
        let trackId: Int?
        let collectionId: Int?
        let artistId: Int?
        let trackName: String?
        let collectionName: String?
        let artistName: String?
        let artworkUrl100: String?
        let primaryGenreName: String?
        let releaseDate: String?
        let trackTimeMillis: Int?
    }
}
