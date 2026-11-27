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
