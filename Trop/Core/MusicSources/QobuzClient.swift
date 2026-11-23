import CryptoKit
import Foundation

/// Standalone Qobuz catalogue + stream resolver. Credentials are supplied by
/// the account holder, never bundled, logged, or fetched from community pools.
/// Refer to Qobuz's API terms before enabling this integration.
struct QobuzCredentials: Codable, Sendable, Equatable, CustomStringConvertible {
    let appId: String
    let appSecret: String
    let userAuthToken: String

    var isComplete: Bool {
        !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !appSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !userAuthToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var description: String { "QobuzCredentials(<redacted>)" }
}

enum QobuzError: Error, Equatable, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidTrack
    case httpStatus(Int)
    case unavailableTrack

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add your Qobuz credentials in Settings → Integrations."
        case .invalidURL, .invalidTrack: return "Invalid Qobuz request."
        case .httpStatus(401), .httpStatus(403): return "Qobuz did not authorize this account."
        case .httpStatus(let code): return "Qobuz returned HTTP \(code)."
        case .unavailableTrack: return "A full Qobuz stream is unavailable for this track."
        }
    }
}

/// Uses Qobuz's documented search and signed getFileUrl API. No credential
/// rotation, session borrowing, automatic login, or subscription bypass.
struct QobuzClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport
    private let clock: @Sendable () -> Int64
    private static let root = "https://www.qobuz.com/api.json/0.2"

    init(
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
        clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970) }
    ) {
        self.transport = transport
        self.clock = clock
    }

    func searchTracks(query: String, limit: Int = 25, credentials: QobuzCredentials) async throws -> [MusicCatalogTrack] {
        guard credentials.isComplete else { throw QobuzError.notConfigured }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let url = try makeURL(
            path: "catalog/search",
            items: [
                URLQueryItem(name: "query", value: term),
                URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
            ],
            credentials: credentials
        )
        let data = try await request(url, credentials: credentials)
        let response = try JSONDecoder().decode(QobuzSearchResponse.self, from: data)
        return response.tracks.items.compactMap { track in
            guard track.streamable == true, track.id > 0, !track.title.isEmpty else { return nil }
            var result = MusicCatalogTrack(
                id: MusicCatalogID(source: .qobuz, rawValue: String(track.id)),
                title: track.title,
                artist: track.performer?.name ?? track.album?.artist?.name ?? "Unknown Artist",
                durationSeconds: max(track.duration ?? 0, 0),
                artworkURL: track.album?.image?.url,
                permalinkURL: nil,
                isStreamable: true
            )
            result.albumTitle = track.album?.title
            return result
        }
    }

    /// Requests a short-lived URL every time a track starts. Only accepts
    /// full-length CD-quality FLAC from an authorized, subscribed account.
    /// Restricted tracks, samples, previews and unexpected formats fail closed.
    func streamURL(trackId: String, credentials: QobuzCredentials) async throws -> URL {
        guard credentials.isComplete else { throw QobuzError.notConfigured }
        guard let id = Int64(trackId), id > 0 else { throw QobuzError.invalidTrack }
        let formatId = 6 // CD-quality FLAC; no quality escalation or downgrade.
        let timestamp = clock()
        let signatureInput = "trackgetFileUrlformat_id\(formatId)intentstreamtrack_id\(id)\(timestamp)\(credentials.appSecret)"
        let signature = Insecure.MD5.hash(data: Data(signatureInput.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let url = try makeURL(
            path: "track/getFileUrl",
            items: [
                URLQueryItem(name: "track_id", value: String(id)),
                URLQueryItem(name: "format_id", value: String(formatId)),
                URLQueryItem(name: "intent", value: "stream"),
                URLQueryItem(name: "request_ts", value: String(timestamp)),
                URLQueryItem(name: "request_sig", value: signature)
            ],
            credentials: credentials
        )
        let data = try await request(url, credentials: credentials)
        let file = try JSONDecoder().decode(QobuzFileResponse.self, from: data)
        guard file.sample != true,
              file.formatId == formatId,
              file.fileType == nil || file.fileType == "full",
              file.restrictions?.isEmpty != false,
              let raw = file.url,
              let resolved = URL(string: raw),
              resolved.scheme?.lowercased() == "https",
              resolved.host != nil else {
            throw QobuzError.unavailableTrack
        }
        return resolved
    }

    private func makeURL(path: String, items: [URLQueryItem], credentials: QobuzCredentials) throws -> URL {
        guard var components = URLComponents(string: "\(Self.root)/\(path)") else {
            throw QobuzError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "app_id", value: credentials.appId)] + items
        guard let url = components.url else { throw QobuzError.invalidURL }
        return url
    }

    private func request(_ url: URL, credentials: QobuzCredentials) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credentials.appId, forHTTPHeaderField: "X-App-Id")
        request.setValue(credentials.userAuthToken, forHTTPHeaderField: "X-User-Auth-Token")
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw QobuzError.invalidURL }
        guard (200..<300).contains(http.statusCode) else { throw QobuzError.httpStatus(http.statusCode) }
        return data
    }
}

private struct QobuzSearchResponse: Decodable {
    let tracks: QobuzTrackPage
}

private struct QobuzTrackPage: Decodable {
    let items: [QobuzTrack]
}

private struct QobuzTrack: Decodable {
    let id: Int64
    let title: String
    let duration: Int?
    let streamable: Bool?
    let performer: QobuzArtist?
    let album: QobuzAlbum?
}

private struct QobuzArtist: Decodable {
    let name: String
}

private struct QobuzAlbum: Decodable {
    let title: String?
    let artist: QobuzArtist?
    let image: QobuzArtwork?
}

private struct QobuzArtwork: Decodable {
    let large: String?
    let extralarge: String?
    let small: String?

    var url: URL? { (extralarge ?? large ?? small).flatMap(URL.init(string:)) }
}

private struct QobuzFileResponse: Decodable {
    let url: String?
    let sample: Bool?
    let formatId: Int?
    let fileType: String?
    let restrictions: [QobuzRestriction]?

    enum CodingKeys: String, CodingKey {
        case url, sample, restrictions
        case formatId = "format_id"
        case fileType = "file_type"
    }
}

private struct QobuzRestriction: Decodable {
    let code: String
}
