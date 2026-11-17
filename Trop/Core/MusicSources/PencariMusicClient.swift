import Foundation

enum PencariMusicError: Error, Equatable, LocalizedError {
    case notConfigured
    case invalidBase
    case invalidQuery
    case httpStatus(Int)
    case originBusy
    case unavailableTrack

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your PencariMusic addon URL in Settings → Integrations."
        case .invalidBase, .invalidQuery:
            return "Invalid PencariMusic request."
        case .httpStatus(let code):
            return "PencariMusic returned HTTP \(code)."
        case .originBusy:
            return "PencariMusic is resolving this track. Try again in a few seconds."
        case .unavailableTrack:
            return "PencariMusic has no playable stream for this track."
        }
    }
}

/// Client for the PencariMusic addon (`/music/search`, `/music/stream/<id>`).
///
/// It speaks the Eclipse/BitChord music surface: search answers tracks with a
/// short code + FLAC metadata, and the stream endpoint resolves that code to a
/// downloadable URL. The redirect goes through their Telegram index, so a 503
/// with `Retry-After` means "warming up", not "missing".
struct PencariMusicClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Bundled addon base so the source works with no setup. Overridable from
    /// settings for advanced users.
    static let defaultBase = "https://stream.pencarimovie.com/66ff097863dedb7ccd8401d5ffe616f3"

    let baseURL: URL
    private let transport: Transport

    init?(
        base: String,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        guard let normalized = Self.normalize(base) else { return nil }
        self.baseURL = normalized
        self.transport = transport
    }

    /// Reads the configured base from settings. Call on the main actor.
    @MainActor
    static func configured() -> PencariMusicClient? {
        PencariMusicClient(base: SettingsStore.shared.pencariMusicBaseURL)
    }

    /// Accepts a bare token base, a `/music` base, or a full `…/music/manifest.json`
    /// URL and reduces it to `scheme://host/<token>`.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let range = s.range(of: "/music/manifest.json") {
            s = String(s[..<range.lowerBound])
        }
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/music") { s.removeLast("/music".count) }
        guard let url = URL(string: s), url.scheme?.hasPrefix("http") == true, url.host != nil else {
            return nil
        }
        return url
    }

    private func endpoint(_ parts: String...) -> URL {
        parts.reduce(baseURL) { $0.appendingPathComponent($1) }
    }

    func searchTracks(query: String, limit: Int = 25) async throws -> [MusicCatalogTrack] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        guard var components = URLComponents(
            url: endpoint("music", "search"),
            resolvingAgainstBaseURL: false
        ) else { throw PencariMusicError.invalidBase }
        components.queryItems = [
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "quality", value: "LOSSLESS")
        ]
        guard let url = components.url else { throw PencariMusicError.invalidQuery }

        let (data, response) = try await transport(URLRequest(url: url, timeoutInterval: 20))
        try Self.validate(response)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        let tracks = decoded.tracks ?? []
        return tracks.prefix(limit).map { track in
            MusicCatalogTrack(
                id: MusicCatalogID(source: .pencari, rawValue: track.id),
                title: track.title,
                artist: track.artist ?? "",
                durationSeconds: track.duration ?? 0,
                artworkURL: Self.realArtwork(track.artworkURL),
                permalinkURL: nil,
                isStreamable: true
            )
        }
    }

    /// Resolves a short code to a playable (FLAC) URL, retrying while the
    /// origin reports it is busy.
    func resolveStreamURL(for rawId: String) async throws -> URL {
        guard baseURL.host != nil else { throw PencariMusicError.invalidBase }
        var lastError: Error = PencariMusicError.unavailableTrack
        for attempt in 0..<3 {
            let url = endpoint("music", "stream", rawId)
            do {
                let (data, response) = try await transport(URLRequest(url: url, timeoutInterval: 45))
                if let http = response as? HTTPURLResponse, http.statusCode == 503 {
                    lastError = PencariMusicError.originBusy
                    let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 3
                    if attempt < 2 {
                        try await Task.sleep(for: .seconds(max(1, min(retry, 8))))
                        continue
                    }
                    throw PencariMusicError.originBusy
                }
                try Self.validate(response)
                let decoded = try JSONDecoder().decode(StreamResponse.self, from: data)
                if let absolute = URL(string: decoded.url), absolute.scheme != nil {
                    return absolute
                }
                // Relative answers resolve against the token base, which must
                // keep its trailing slash so the token isn't dropped.
                let baseDir = baseURL.appendingPathComponent("")
                guard let streamURL = URL(string: decoded.url, relativeTo: baseDir)?.absoluteURL else {
                    throw PencariMusicError.unavailableTrack
                }
                return streamURL
            } catch let error as PencariMusicError {
                if error == .originBusy, attempt < 2 {
                    lastError = error
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    /// Single, short attempt with no retry/backoff — used on the automatic
    /// "prefer lossless" path where latency matters and failure just falls
    /// back to YouTube.
    func resolveStreamURLFast(for rawId: String) async throws -> URL {
        let url = endpoint("music", "stream", rawId)
        let (data, response) = try await transport(URLRequest(url: url, timeoutInterval: 12))
        if let http = response as? HTTPURLResponse, http.statusCode == 503 {
            throw PencariMusicError.originBusy
        }
        try Self.validate(response)
        let decoded = try JSONDecoder().decode(StreamResponse.self, from: data)
        if let absolute = URL(string: decoded.url), absolute.scheme != nil {
            return absolute
        }
        let baseDir = baseURL.appendingPathComponent("")
        guard let streamURL = URL(string: decoded.url, relativeTo: baseDir)?.absoluteURL else {
            throw PencariMusicError.unavailableTrack
        }
        return streamURL
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw PencariMusicError.httpStatus(http.statusCode)
        }
    }

    private static func realArtwork(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw) else { return nil }
        // The addon ships a generic Telegram placeholder when it has no cover.
        if url.lastPathComponent.contains("tg-placeholder") { return nil }
        return url
    }
}

private struct SearchResponse: Decodable {
    let tracks: [Track]?

    struct Track: Decodable {
        let id: String
        let title: String
        let artist: String?
        let duration: Int?
        let artworkURL: String?
        let format: String?
    }
}

private struct StreamResponse: Decodable {
    let url: String
    let format: String?
    let mimeType: String?
}
