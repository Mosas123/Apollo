import Foundation

/// Podcast metadata enrichment: Podcast Index first (when configured), then
/// iTunes' free podcast search as fallback. Kept separate from the music
/// resolver so shows never get matched against songs.
enum PodcastMetadataResolver {
    static func enrich(title: String, author: String) async -> ResolvedMetadata? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        if let client = PodcastIndexClient.fromSettings(),
           let feed = try? await client.search("\(title) \(author)").first {
            return ResolvedMetadata(
                title: feed.title ?? title,
                artist: feed.displayAuthor.isEmpty ? author : feed.displayAuthor,
                album: nil,
                year: nil,
                artworkURL: feed.artworkURL,
                source: "Podcast Index"
            )
        }

        return await iTunesPodcast(title: title, author: author)
    }

    private struct ITunesPodcastResponse: Decodable {
        struct Result: Decodable {
            let collectionName: String?
            let artistName: String?
            let artworkUrl600: String?
            let feedUrl: String?
        }
        let results: [Result]
    }

    private static func iTunesPodcast(title: String, author: String) async -> ResolvedMetadata? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(title) \(author)"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ITunesPodcastResponse.self, from: data),
              let best = decoded.results.first else {
            return nil
        }

        return ResolvedMetadata(
            title: best.collectionName ?? title,
            artist: best.artistName ?? author,
            album: nil,
            year: nil,
            artworkURL: best.artworkUrl600.flatMap(URL.init(string:)),
            source: "iTunes"
        )
    }
}
