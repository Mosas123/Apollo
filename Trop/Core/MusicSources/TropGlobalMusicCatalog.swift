import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public sitewide listening statistics. This is browse metadata, not a
/// library item, playback credential, audio stream, or YouTube Music feed.
struct TropGlobalRecording: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let listenCount: Int
    let source: String
    // Reference metadata may be unknown; never invent a duration from artwork.
    let durationSeconds: Int?

    init(
        id: String, title: String, artist: String,
        album: String?, listenCount: Int, source: String = "ListenBrainz",
        durationSeconds: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.listenCount = listenCount
        self.source = source
        self.durationSeconds = durationSeconds
    }
}

enum TropGlobalCatalogError: Error {
    case invalidResponse
    case unavailable
    case oversizedResponse
}

/// An independent discovery source usable on first launch with an empty
/// Library V2. Actual audio is chosen separately by Trop Match on user tap.
/// No user identity, auth token, search history or private data is transmitted.
actor TropGlobalMusicCatalog {
    static let shared = TropGlobalMusicCatalog()

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport
    private var cached: (updated: Date, items: [TropGlobalRecording])?
    private static let ttl: TimeInterval = 30 * 60
    private static let maximumBytes = 1024 * 1024

    init(transport: @escaping Transport = {
        try await URLSession.shared.data(for: $0)
    }) {
        self.transport = transport
    }

    func popularRecordings(forceRefresh: Bool = false) async throws
        -> [TropGlobalRecording] {
        if !forceRefresh, let cached,
           Date().timeIntervalSince(cached.updated) < Self.ttl {
            return cached.items
        }
        var failure: Error?
        // This is explicitly ListenBrainz sitewide listening activity.
        // It is not a fabricated 'For You' algorithm or global chart.
        for period in ["week", "month"] {
            do {
                let items = try await fetch(period: period)
                if !items.isEmpty {
                    cached = (Date(), items)
                    return items
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failure = error
            }
        }
        if let cached { return cached.items }
        if let failure { throw failure }
        return []
    }

    private func fetch(period: String) async throws -> [TropGlobalRecording] {
        guard var parts = URLComponents(
            string: "https://api.listenbrainz.org/1/stats/sitewide/recordings"
        ) else { throw TropGlobalCatalogError.invalidResponse }
        parts.queryItems = [
            URLQueryItem(name: "range", value: period),
            URLQueryItem(name: "count", value: "100"),
            URLQueryItem(name: "offset", value: "0")
        ]
        guard let url = parts.url else {
            throw TropGlobalCatalogError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Trop/1.0 (https://github.com/Mosas123/Trop)",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try Task.checkCancellation()
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw TropGlobalCatalogError.invalidResponse
        }
        if http.statusCode == 204 { return [] }
        guard http.statusCode == 200 else {
            throw TropGlobalCatalogError.unavailable
        }
        guard data.count <= Self.maximumBytes else {
            throw TropGlobalCatalogError.oversizedResponse
        }
        let decoded = try JSONDecoder().decode(SiteStats.self, from: data)
        var seen = Set<String>()
        var perArtist: [String: Int] = [:]
        // Public ListenBrainz activity is often concentrated in one fanbase.
        // Cap *display candidates* per performer while retaining source order.
        return decoded.payload.recordings.compactMap { row -> TropGlobalRecording? in
            let title = row.track_name.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = row.artist_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...180).contains(title.count),
                  (2...180).contains(artist.count),
                  row.listen_count > 0 else { return nil }
            let mbid = row.recording_mbid.flatMap {
                UUID(uuidString: $0)?.uuidString.lowercased()
            }
            let key = mbid ?? "\(artist.lowercased())|\(title.lowercased())"
            guard seen.insert(key).inserted else { return nil }
            let artistKey = artist.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ).lowercased()
            guard perArtist[artistKey, default: 0] < 2 else { return nil }
            perArtist[artistKey, default: 0] += 1
            let album = row.release_name?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return TropGlobalRecording(
                id: key, title: title, artist: artist,
                album: album?.isEmpty == true ? nil : album,
                listenCount: row.listen_count
            )
        }
    }

    private struct SiteStats: Decodable {
        let payload: Payload
        struct Payload: Decodable {
            let recordings: [Recording]
        }
        struct Recording: Decodable {
            let track_name: String
            let artist_name: String
            let recording_mbid: String?
            let release_name: String?
            let listen_count: Int
        }
    }
}
