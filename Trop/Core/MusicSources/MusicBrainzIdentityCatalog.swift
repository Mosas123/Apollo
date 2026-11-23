import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// MusicBrainz identifies *recordings*, artists and release groups; none of
/// these IDs is a YouTube video ID or a stream URL.
enum MusicBrainzEntityKind: String, Codable, Hashable, Sendable {
    case recording
    case artist
    case releaseGroup = "release-group"
}

struct MusicBrainzEntityID: Codable, Hashable, Sendable {
    let kind: MusicBrainzEntityKind
    let mbid: String

    init?(kind: MusicBrainzEntityKind, mbid: String) {
        guard let uuid = UUID(uuidString: mbid) else { return nil }
        self.kind = kind
        self.mbid = uuid.uuidString.lowercased()
    }

    /// Deliberately *not* the legacy SongItem.videoId identity.
    var storageKey: String { "musicbrainz:\(kind.rawValue):\(mbid)" }

    var catalogID: MusicCatalogID {
        MusicCatalogID(source: .musicbrainz, rawValue: "\(kind.rawValue):\(mbid)")
    }
}

struct MusicBrainzRecording: Sendable, Equatable {
    let id: MusicBrainzEntityID
    let title: String
    let artist: String
    let durationSeconds: Int?
    let isrcs: [String]
    let score: Int?
}

struct MusicBrainzAlbum: Sendable, Equatable {
    let id: MusicBrainzEntityID
    let title: String
    let artist: String
    let primaryType: String?
    let firstReleaseDate: String?
    let score: Int?
}

struct MusicBrainzArtist: Sendable, Equatable {
    let id: MusicBrainzEntityID
    let name: String
    let disambiguation: String?
    let score: Int?
}

enum MusicBrainzCatalogError: Error, Equatable {
    case invalidRequest
    case httpStatus(Int)
    case oversizedResponse
}

/// One shared limiter across *all* catalogue endpoints and client instances.
/// Reserve the slot before suspension: concurrent searches cannot bypass 1/s.
/// A future commercial release requires separately authorized API access.
actor MusicBrainzRequestLimiter {
    static let shared = MusicBrainzRequestLimiter()
    private var nextSlot: ContinuousClock.Instant?
    private let interval: Duration

    init(interval: Duration = .seconds(1)) {
        self.interval = interval
    }

    func waitForSlot() async throws {
        try Task.checkCancellation()
        let clock = ContinuousClock()
        let now = clock.now
        let slot = nextSlot.map { max(now, $0) } ?? now
        nextSlot = slot.advanced(by: interval)
        let remaining = now.duration(to: slot)
        if remaining > .zero {
            try await Task.sleep(for: remaining)
        }
        try Task.checkCancellation()
    }
}

/// Read-only catalogue discovery. Search results are CANDIDATES, not proof
/// that two releases share an audio master, and NEVER playable sources.
/// No SongItem conversion, queue mutation, streaming or YouTube fallbacks.
struct MusicBrainzIdentityCatalog: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport
    private let limiter: MusicBrainzRequestLimiter
    private static let maxResponseBytes = 2 * 1024 * 1024
    private static let userAgent = "Trop/1.0 (https://github.com/Mosas123/Trop)"

    init(
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
        limiter: MusicBrainzRequestLimiter = .shared
    ) {
        self.transport = transport
        self.limiter = limiter
    }

    func searchRecordings(title: String, artist: String, limit: Int = 25) async throws -> [MusicBrainzRecording] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return [] }
        let term = "recording:\(Self.quoted(title))"
            + (artist.isEmpty ? "" : " AND artist:\(Self.quoted(artist))")
        return try await matchingRecordings(term: term, limit: limit)
    }

    /// Global artist searches must also find music by that performer, even
    /// when the typed phrase is not part of any track's title.
    func searchRecordingsByArtist(
        artist: String, limit: Int = 25
    ) async throws -> [MusicBrainzRecording] {
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard artist.count >= 2 else { return [] }
        return try await matchingRecordings(
            term: "artist:\(Self.quoted(artist))", limit: limit
        )
    }

    private func matchingRecordings(
        term: String, limit: Int
    ) async throws -> [MusicBrainzRecording] {
        let page: RecordingPage = try await search(entity: "recording", term: term, limit: limit)
        var seen = Set<String>()
        return page.recordings.compactMap { item in
            guard item.video != true,
                  let id = MusicBrainzEntityID(kind: .recording, mbid: item.id),
                  !item.title.isEmpty,
                  let credits = item.artistCredit,
                  !credits.rendered.isEmpty,
                  seen.insert(id.storageKey).inserted else { return nil }
            return MusicBrainzRecording(
                id: id,
                title: item.title,
                artist: credits.rendered,
                durationSeconds: item.length.map { max(0, $0 / 1_000) },
                isrcs: (item.isrcs ?? []).filter { value in
                    value.count == 12 && value.utf8.allSatisfy { byte in
                        (48...57).contains(byte) || (65...90).contains(byte)
                    }
                },
                score: item.score
            )
        }
    }

    func searchArtists(query: String, limit: Int = 25) async throws -> [MusicBrainzArtist] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let page: ArtistPage = try await search(entity: "artist", term: "artist:\(Self.quoted(query))", limit: limit)
        var seen = Set<String>()
        return page.artists.compactMap { item in
            guard let id = MusicBrainzEntityID(kind: .artist, mbid: item.id),
                  !item.name.isEmpty,
                  seen.insert(id.storageKey).inserted else { return nil }
            return MusicBrainzArtist(
                id: id, name: item.name,
                disambiguation: item.disambiguation, score: item.score
            )
        }
    }

    func searchAlbums(title: String, artist: String, limit: Int = 25) async throws -> [MusicBrainzAlbum] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return [] }
        let term = "releasegroup:\(Self.quoted(title))"
            + (artist.isEmpty ? "" : " AND artist:\(Self.quoted(artist))")
        let page: AlbumPage = try await search(entity: "release-group", term: term, limit: limit)
        var seen = Set<String>()
        return page.albums.compactMap { item in
            guard let id = MusicBrainzEntityID(kind: .releaseGroup, mbid: item.id),
                  !item.title.isEmpty,
                  let credits = item.artistCredit,
                  !credits.rendered.isEmpty,
                  seen.insert(id.storageKey).inserted else { return nil }
            return MusicBrainzAlbum(
                id: id, title: item.title, artist: credits.rendered,
                primaryType: item.primaryType, firstReleaseDate: item.firstReleaseDate,
                score: item.score
            )
        }
    }

    private func search<T: Decodable>(entity: String, term: String, limit: Int) async throws -> T {
        guard var parts = URLComponents(string: "https://musicbrainz.org/ws/2/\(entity)") else {
            throw MusicBrainzCatalogError.invalidRequest
        }
        parts.queryItems = [
            URLQueryItem(name: "query", value: term),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ]
        guard let url = parts.url else { throw MusicBrainzCatalogError.invalidRequest }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try await limiter.waitForSlot()
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else {
            throw MusicBrainzCatalogError.invalidRequest
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MusicBrainzCatalogError.httpStatus(http.statusCode)
        }
        guard data.count <= Self.maxResponseBytes else {
            throw MusicBrainzCatalogError.oversizedResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func quoted(_ raw: String) -> String {
        // Bound each phrase before escaping: truncating a complete Lucene
        // expression could cut its closing quote and invalidate the query.
        let limited = String(raw.prefix(120))
        let escaped = limited.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private struct MBArtistStub: Decodable {
    let name: String?
}

/// Artist-credit is a mixed array of credited artists and literal join phrases.
/// Decoding it as an array of dictionaries would reject collaborations.
private struct MBCreditPiece: Decodable {
    let display: String

    private enum CodingKeys: String, CodingKey { case name, artist }

    init(from decoder: Decoder) throws {
        if let literal = try? decoder.singleValueContainer().decode(String.self) {
            display = literal
            return
        }
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        display = try fields.decodeIfPresent(String.self, forKey: .name)
            ?? fields.decodeIfPresent(MBArtistStub.self, forKey: .artist)?.name
            ?? ""
    }
}

private extension Array where Element == MBCreditPiece {
    var rendered: String { map(\.display).joined().trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct RecordingPage: Decodable {
    struct Recording: Decodable {
        let id: String
        let title: String
        let length: Int?
        let score: Int?
        let video: Bool?
        let isrcs: [String]?
        let artistCredit: [MBCreditPiece]?
        enum CodingKeys: String, CodingKey {
            case id, title, length, score, video, isrcs
            case artistCredit = "artist-credit"
        }
    }
    let recordings: [Recording]
}

private struct ArtistPage: Decodable {
    struct Artist: Decodable {
        let id: String
        let name: String
        let disambiguation: String?
        let score: Int?
    }
    let artists: [Artist]
}

private struct AlbumPage: Decodable {
    struct Album: Decodable {
        let id: String
        let title: String
        let score: Int?
        let primaryType: String?
        let firstReleaseDate: String?
        let artistCredit: [MBCreditPiece]?
        enum CodingKeys: String, CodingKey {
            case id, title, score
            case primaryType = "primary-type"
            case firstReleaseDate = "first-release-date"
            case artistCredit = "artist-credit"
        }
    }
    let albums: [Album]
    enum CodingKeys: String, CodingKey { case albums = "release-groups" }
}
