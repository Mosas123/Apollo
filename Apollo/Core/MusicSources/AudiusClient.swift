import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read-only Audius integration. No keys, account cookies or premium-track bypasses.
/// Endpoint reference: https://docs.audius.co/api/
struct AudiusClient: MusicCatalogProvider {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let source: MusicCatalogSource = .audius
    private let transport: Transport
    private static let root = "https://api.audius.co/v1"

    init(transport: @escaping Transport = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.transport = transport
    }

    func searchTracks(query: String, limit: Int = 25) async throws -> [MusicCatalogTrack] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var components = URLComponents(string: "\(Self.root)/tracks/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ]
        guard let url = components?.url else { throw MusicCatalogError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Apollo/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else {
            throw MusicCatalogError.invalidURL
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MusicCatalogError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(AudiusSearchResponse.self, from: data).data.compactMap { item in
            // `is_streamable` can be false for paid/unlocked tracks. Never
            // silently fall back to a preview or bypass an access gate.
            guard item.isStreamable == true,
                  item.isStreamGated != true,
                  item.isAvailable != false,
                  item.isDeleted != true,
                  !item.id.isEmpty,
                  !item.title.isEmpty else { return nil }
            return MusicCatalogTrack(
                id: MusicCatalogID(source: .audius, rawValue: item.id),
                title: item.title,
                artist: item.user?.name ?? "Unknown Artist",
                durationSeconds: max(item.duration ?? 0, 0),
                artworkURL: item.artwork?.url,
                permalinkURL: Self.permalinkURL(item.permalink),
                isStreamable: true
            )
        }
    }

    /// The documented endpoint redirects to an MP3 stream. The audio player
    /// should follow redirects and handle 401/403/429 at playback time.
    func streamURL(for track: MusicCatalogTrack) throws -> URL {
        guard track.id.source == .audius else { throw MusicCatalogError.wrongProvider }
        guard track.isStreamable else { throw MusicCatalogError.unavailableTrack }
        let id = track.id.rawValue
        guard !id.isEmpty,
              id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              let url = URL(string: "\(Self.root)/tracks/\(id)/stream") else {
            throw MusicCatalogError.invalidURL
        }
        return url
    }

    private static func permalinkURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") {
            return URL(string: "https://audius.co\(raw)")
        }
        guard let url = URL(string: raw), url.scheme == "https",
              url.host == "audius.co" || url.host == "www.audius.co" else { return nil }
        return url
    }
}

private struct AudiusSearchResponse: Decodable {
    let data: [AudiusTrackResponse]
}

private struct AudiusTrackResponse: Decodable {
    let id: String
    let title: String
    let user: AudiusUser?
    let duration: Int?
    let artwork: AudiusArtwork?
    let permalink: String?
    let isStreamable: Bool?
    let isStreamGated: Bool?
    let isAvailable: Bool?
    let isDeleted: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, user, duration, artwork, permalink
        case isStreamable = "is_streamable"
        case isStreamGated = "is_stream_gated"
        case isAvailable = "is_available"
        case isDeleted = "is_delete"
    }
}

private struct AudiusUser: Decodable {
    let name: String?
}

/// Audius installations may return an object of resolutions or one artwork URL.
private struct AudiusArtwork: Decodable {
    let url: URL?

    init(from decoder: Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self) {
            url = URL(string: raw)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let large = try container.decodeIfPresent(String.self, forKey: .large)
        let medium = try container.decodeIfPresent(String.self, forKey: .medium)
        let small = try container.decodeIfPresent(String.self, forKey: .small)
        url = (large ?? medium ?? small).flatMap(URL.init(string:))
    }

    enum CodingKeys: String, CodingKey {
        case large = "1000x1000"
        case medium = "480x480"
        case small = "150x150"
    }
}
