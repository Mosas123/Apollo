import Foundation
import CryptoKit

enum PodcastIndexError: LocalizedError {
    case notConfigured
    case http(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Podcast Index is not configured."
        case .http(let code): return "Podcast Index returned HTTP \(code)."
        case .decoding: return "Could not read the Podcast Index response."
        }
    }
}

struct PodcastIndexFeed: Decodable, Sendable {
    let id: Int?
    let title: String?
    let author: String?
    let artist: String?
    let image: String?
    let artwork: String?
    let itunesId: Int?
    let feedUrl: String?

    var artworkURL: URL? {
        (artwork ?? image).flatMap(URL.init(string:))
    }

    var displayAuthor: String {
        let value = (artist?.isEmpty == false ? artist : author) ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Podcast Index API client (https://podcastindex.org). Auth is the documented
/// `X-Auth-Key` + `X-Auth-Date` + `Authorization: sha1(key + secret + date)`.
struct PodcastIndexClient {
    let key: String
    let secret: String

    static func fromSettings() -> PodcastIndexClient? {
        let settings = SettingsStore.shared
        let key = settings.podcastIndexKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = settings.podcastIndexSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !secret.isEmpty else { return nil }
        return PodcastIndexClient(key: key, secret: secret)
    }

    func search(_ query: String, max: Int = 5) async throws -> [PodcastIndexFeed] {
        try await get(
            path: "search/byterm",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "max", value: "\(max)")
            ]
        )
    }

    /// Trending podcasts — used for local discovery when the AI is off.
    func trending(max: Int = 20) async throws -> [PodcastIndexFeed] {
        try await get(path: "podcasts/trending", queryItems: [URLQueryItem(name: "max", value: "\(max)")])
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> [PodcastIndexFeed] {
        var components = URLComponents(string: "https://api.podcastindex.org/api/1.0/\(path)")
        components?.queryItems = queryItems
        guard let url = components?.url else { throw PodcastIndexError.notConfigured }

        let date = String(Int(Date().timeIntervalSince1970))
        let hash = Insecure.SHA1
            .hash(data: Data((key + secret + date).utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "X-Auth-Key")
        request.setValue(date, forHTTPHeaderField: "X-Auth-Date")
        request.setValue(hash, forHTTPHeaderField: "Authorization")
        request.setValue("Thrum/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw PodcastIndexError.http(status) }

        struct Envelope: Decodable { let feeds: [PodcastIndexFeed]? }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw PodcastIndexError.decoding
        }
        return envelope.feeds ?? []
    }
}
