import Foundation

struct MusicBrainzRecording: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artistCredit: String
    let lengthMS: Int?
    let isrcs: [String]
    let releaseDate: String?
    let score: Int
}

enum MusicBrainzError: Error, Sendable {
    case invalidResponse
    case http(Int)
}

actor MusicBrainzTagCache {
    static let shared = MusicBrainzTagCache()
    private struct Entry { let tags: [String]; let at: Date }
    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 24 * 60 * 60

    func tags(for key: String) -> [String]? {
        guard let entry = entries[key], Date().timeIntervalSince(entry.at) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.tags
    }

    func store(_ tags: [String], for key: String) {
        entries[key] = Entry(tags: tags, at: Date())
    }
}

actor MusicBrainzCache {
    static let shared = MusicBrainzCache()

    private struct Entry {
        let recording: MusicBrainzRecording?
        let at: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 24 * 60 * 60
    private let maxEntries = 512

    func recording(for key: String) -> MusicBrainzRecording?? {
        guard let entry = entries[key] else { return nil }
        guard Date().timeIntervalSince(entry.at) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.recording
    }

    func store(_ recording: MusicBrainzRecording?, for key: String) {
        if entries.count >= maxEntries {
            let cutoff = Date().addingTimeInterval(-ttl)
            entries = entries.filter { $0.value.at >= cutoff }
            if entries.count >= maxEntries { entries.removeAll(keepingCapacity: true) }
        }
        entries[key] = Entry(recording: recording, at: Date())
    }
}

/// MusicBrainz allows one request per second; all lookups share one gate.
actor MusicBrainzGate {
    static let shared = MusicBrainzGate()
    private var lastRequest: Date?

    func wait() async {
        let interval: TimeInterval = 1.1
        if let lastRequest {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < interval {
                let nanoseconds = UInt64((interval - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
        lastRequest = Date()
    }
}

struct MusicBrainzClient: @unchecked Sendable {
    private let session: URLSession
    private let userAgent = "Apollo/0.14.0 (com.cl0udly.Apollo)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(
        title: String,
        artist: String,
        durationMS: Int?,
        limit: Int = 5
    ) async throws -> MusicBrainzRecording? {
        let normalizedTitle = TextMatch.normalizeTitle(title)
        let normalizedArtist = TextMatch.normalizeArtist(artist)
        guard !normalizedTitle.isEmpty else { return nil }

        let key = "\(normalizedTitle)|\(normalizedArtist)|\(durationMS ?? 0)"
        if let cached = await MusicBrainzCache.shared.recording(for: key) {
            return cached
        }

        var query = "recording:\"\(title)\""
        if !artist.isEmpty { query += " AND artist:\"\(artist)\"" }

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 10))))
        ]
        guard let url = components?.url else { throw MusicBrainzError.invalidResponse }

        await MusicBrainzGate.shared.wait()

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MusicBrainzError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MusicBrainzError.http(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let best = bestMatch(
            title: normalizedTitle,
            artist: normalizedArtist,
            durationMS: durationMS,
            candidates: decoded.recordings
        )
        await MusicBrainzCache.shared.store(best, for: key)
        return best
    }

    /// Artist tags/genres for genre-continuity radio. No API key required.
    func artistTags(name: String, limit: Int = 8) async -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let key = trimmed.lowercased()
        if let cached = await MusicBrainzTagCache.shared.tags(for: key) {
            return Array(cached.prefix(limit))
        }

        guard let artistID = await artistID(for: trimmed) else {
            await MusicBrainzTagCache.shared.store([], for: key)
            return []
        }

        await MusicBrainzGate.shared.wait()
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/artist/\(artistID)")
        components?.queryItems = [
            URLQueryItem(name: "inc", value: "tags+genres"),
            URLQueryItem(name: "fmt", value: "json")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ArtistDetailResponse.self, from: data) else {
            return []
        }

        var candidates = MusicBrainzTagPolicy.candidates(
            genres: (decoded.genres ?? []).map(\.name),
            tags: (decoded.tags ?? []).map { (name: $0.name, count: $0.count) }
        )
        var result = MusicBrainzTagPolicy.select(candidates, limit: 20)
            .filter { $0.lowercased() != trimmed.lowercased() }

        // Many artists have no tags on the artist entity but do have them on
        // their releases. One extra gated request keeps genre stations alive
        // without falling back to Last.fm or a different API key.
        if result.isEmpty {
            candidates = await releaseGroupTagCandidates(artistID: artistID)
            result = MusicBrainzTagPolicy.select(candidates, limit: 20)
                .filter { $0.lowercased() != trimmed.lowercased() }
        }

        await MusicBrainzTagCache.shared.store(result, for: key)
        return Array(result.prefix(limit))
    }

    private func releaseGroupTagCandidates(artistID: String) async -> [MusicBrainzTagCandidate] {
        await MusicBrainzGate.shared.wait()
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release-group")
        components?.queryItems = [
            URLQueryItem(name: "artist", value: artistID),
            URLQueryItem(name: "inc", value: "tags+genres"),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "25")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ReleaseGroupBrowseResponse.self, from: data) else {
            return []
        }

        var weights: [String: (name: String, weight: Int)] = [:]
        func add(_ name: String, _ weight: Int) {
            let key = name.lowercased()
            if let existing = weights[key] {
                weights[key] = (existing.name, existing.weight + weight)
            } else {
                weights[key] = (name, weight)
            }
        }
        for group in decoded.groups {
            for genre in group.genres ?? [] { add(genre.name, 10) }
            for tag in group.tags ?? [] { add(tag.name, tag.count ?? 0) }
        }
        return weights.values.map { MusicBrainzTagCandidate(name: $0.name, weight: $0.weight) }
    }

    private func artistID(for name: String) async -> String? {
        await MusicBrainzGate.shared.wait()
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/artist")
        components?.queryItems = [
            URLQueryItem(name: "query", value: name),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "3")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ArtistSearchResponse.self, from: data),
              !decoded.artists.isEmpty else {
            return nil
        }

        let wanted = TextMatch.normalizeArtist(name)
        if let exact = decoded.artists.first(where: { TextMatch.normalizeArtist($0.name) == wanted }) {
            return exact.id
        }
        return decoded.artists.first(where: { ($0.score ?? 0) >= 90 })?.id
    }

    private func bestMatch(
        title: String,
        artist: String,
        durationMS: Int?,
        candidates: [Response.Recording]
    ) -> MusicBrainzRecording? {
        for candidate in candidates {
            let candidateTitle = TextMatch.normalizeTitle(candidate.title)
            guard candidateTitle == title || candidateTitle.contains(title) || title.contains(candidateTitle) else {
                continue
            }

            let artistCredit = candidate.artistCredit.map(\.name).joined(separator: ", ")
            if !artist.isEmpty, !artistCredit.isEmpty {
                let candidateArtist = TextMatch.normalizeArtist(artistCredit)
                guard candidateArtist.contains(artist) || artist.contains(candidateArtist) else { continue }
            }

            if let durationMS, let length = candidate.length, length > 0 {
                guard abs(length - durationMS) <= 15_000 else { continue }
            }

            return MusicBrainzRecording(
                id: candidate.id,
                title: candidate.title,
                artistCredit: artistCredit,
                lengthMS: candidate.length,
                isrcs: candidate.isrcs ?? [],
                releaseDate: candidate.releases?.first?.date,
                score: candidate.score ?? 0
            )
        }
        return nil
    }

    private struct ReleaseGroupBrowseResponse: Decodable {
        let groups: [ReleaseGroup]

        enum CodingKeys: String, CodingKey {
            case groups = "release-groups"
        }

        struct ReleaseGroup: Decodable {
            let genres: [ArtistDetailResponse.Genre]?
            let tags: [ArtistDetailResponse.Tag]?
        }
    }

    private struct ArtistSearchResponse: Decodable {
        let artists: [SearchArtist]
        struct SearchArtist: Decodable {
            let id: String
            let name: String
            let score: Int?
        }
    }

    private struct ArtistDetailResponse: Decodable {
        let genres: [Genre]?
        let tags: [Tag]?
        struct Genre: Decodable {
            let name: String
        }
        struct Tag: Decodable {
            let name: String
            let count: Int?
        }
    }

    private struct Response: Decodable {
        let recordings: [Recording]

        struct Recording: Decodable {
            let id: String
            let title: String
            let length: Int?
            let isrcs: [String]?
            let score: Int?
            let artistCredit: [ArtistCredit]
            let releases: [Release]?

            enum CodingKeys: String, CodingKey {
                case id, title, length, isrcs, score, releases
                case artistCredit = "artist-credit"
            }

            struct ArtistCredit: Decodable {
                let name: String
            }

            struct Release: Decodable {
                let date: String?
            }
        }
    }
}
