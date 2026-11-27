import Foundation

enum AppleChartKind: String, Sendable {
    case songs
    case albums
}

struct AppleChartItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
}

actor AppleChartsCache {
    static let shared = AppleChartsCache()
    private struct Entry { let items: [AppleChartItem]; let at: Date }
    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 6 * 60 * 60

    func items(for key: String) -> [AppleChartItem]? {
        guard let entry = entries[key], Date().timeIntervalSince(entry.at) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.items
    }

    func store(_ items: [AppleChartItem], for key: String) {
        entries[key] = Entry(items: items, at: Date())
    }
}

struct AppleChartsClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func top(kind: AppleChartKind, country: String = "us", limit: Int = 8) async -> [AppleChartItem] {
        let storefront = country.lowercased()
        let key = "\(storefront)|\(kind.rawValue)|\(limit)"
        if let cached = await AppleChartsCache.shared.items(for: key) { return cached }

        let urlString = "https://rss.applemarketingtools.com/api/v2/\(storefront)/music/most-played/\(limit)/\(kind.rawValue).json"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            return []
        }

        let items = decoded.feed.results.compactMap { result -> AppleChartItem? in
            let title = result.name
            let artist = result.artistName
            guard !title.isEmpty, !artist.isEmpty else { return nil }
            return AppleChartItem(
                id: result.id,
                title: title,
                artist: artist,
                artworkURL: Self.upscaledArtwork(result.artworkUrl100)
            )
        }

        await AppleChartsCache.shared.store(items, for: key)
        return items
    }

    private static func upscaledArtwork(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        return URL(string: value.replacingOccurrences(of: "100x100", with: "600x600"))
    }

    private struct Response: Decodable {
        let feed: Feed
        struct Feed: Decodable {
            let results: [Result]
        }
        struct Result: Decodable {
            let id: String
            let name: String
            let artistName: String
            let artworkUrl100: String?
        }
    }
}
