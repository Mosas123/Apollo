import Foundation

struct PodcastFeedInfo: Hashable, Sendable {
    let title: String
    let author: String?
    let feedURL: URL?
    let artworkURL: URL?
    let collectionID: Int?
}

actor ITunesPodcastDirectory {
    static let shared = ITunesPodcastDirectory()

    private struct Entry {
        let feed: PodcastFeedInfo?
        let at: Date
    }

    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 6 * 60 * 60

    func feed(for show: String) async -> PodcastFeedInfo? {
        let key = show.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let entry = cache[key], Date().timeIntervalSince(entry.at) < ttl {
            return entry.feed
        }

        let country = Locale.current.region?.identifier.lowercased() ?? "us"
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: show),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            cache[key] = Entry(feed: nil, at: Date())
            return nil
        }

        let wanted = TextMatch.normalizeTitle(show)
        let candidates = decoded.results.compactMap { result -> (PodcastFeedInfo, Int)? in
            guard let name = result.collectionName, let feed = result.feedUrl,
                  let feedURL = URL(string: feed) else { return nil }
            let normalized = TextMatch.normalizeTitle(name)
            var score = 0
            if normalized == wanted { score += 100 }
            else if !wanted.isEmpty, normalized.contains(wanted) || wanted.contains(normalized) { score += 50 }
            else if let author = result.artistName,
                    TextMatch.normalizeArtist(author) == TextMatch.normalizeArtist(show) { score += 30 }
            else { return nil }
            let art = result.artworkUrl600.flatMap(URL.init(string:))
            return (
                PodcastFeedInfo(
                    title: name,
                    author: result.artistName,
                    feedURL: feedURL,
                    artworkURL: art,
                    collectionID: result.collectionId
                ),
                score
            )
        }

        let best = candidates.max { $0.1 < $1.1 }?.0
        cache[key] = Entry(feed: best, at: Date())
        return best
    }

    private struct Response: Decodable {
        let results: [Result]
        struct Result: Decodable {
            let collectionName: String?
            let artistName: String?
            let feedUrl: String?
            let artworkUrl600: String?
            let collectionId: Int?
        }
    }
}
