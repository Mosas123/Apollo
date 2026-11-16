import Foundation

/// AI recommendations: the model suggests from the listener's profile and each
/// suggestion is validated against YouTube Music before it's shown — the same
/// pattern Nuvio uses with TMDB, adapted to music. Two separate shelves:
/// songs ("For You") and new artists ("Artistas para ti"). Cached, built lazily.
@MainActor
enum ForYouService {
    private static var cachedSongs: (date: Date, songs: [SongItem])?
    private static var cachedArtists: (date: Date, artists: [ArtistItem])?
    private static let ttl: TimeInterval = 60 * 60 * 6

    // MARK: - Songs

    static func musicSongs(force: Bool = false) async -> [SongItem] {
        if !force, let cached = cachedSongs, Date().timeIntervalSince(cached.date) < ttl {
            return cached.songs
        }
        guard let client = AIProviderClient.configured() else {
            return cachedSongs?.songs ?? []
        }

        let profile = await loadProfile()
        guard !profile.artists.isEmpty || !profile.liked.isEmpty else {
            return cachedSongs?.songs ?? []
        }

        let prompt = """
        You are a music recommendation engine. The listener follows these artists: \
        \(profile.artists.joined(separator: ", ")). Their liked songs: \(profile.liked.joined(separator: "; ")).
        Recommend 20 songs they likely haven't heard, mixing familiar artists with closely related ones.
        Reply ONLY with a JSON array of objects: [{"artist":"...","title":"..."}]. No prose.
        """

        guard let text = try? await client.complete(prompt),
              let suggestions = parseSuggestions(text), !suggestions.isEmpty else {
            return cachedSongs?.songs ?? []
        }

        var songs: [SongItem] = []
        var seen = Set<String>()
        for suggestion in suggestions {
            let query = "\(suggestion.artist) \(suggestion.title)"
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty,
                  let raw = try? await SearchService.shared.search(query: query) else { continue }
            let sections = SearchParser.parseSearchResults(from: raw)
            let song = sections
                .first(where: { $0.title == "Songs" })?
                .items
                .compactMap { item -> SongItem? in
                    if case .song(let song) = item { return song }
                    return nil
                }
                .first
            guard let song, seen.insert(song.videoId).inserted else { continue }
            songs.append(song)
            if songs.count >= 15 { break }
        }

        if !songs.isEmpty {
            cachedSongs = (Date(), songs)
            return songs
        }
        return cachedSongs?.songs ?? []
    }

    // MARK: - Artists

    static func artists(force: Bool = false) async -> [ArtistItem] {
        if !force, let cached = cachedArtists, Date().timeIntervalSince(cached.date) < ttl {
            return cached.artists
        }
        guard let client = AIProviderClient.configured() else {
            return cachedArtists?.artists ?? []
        }

        let profile = await loadProfile()
        guard !profile.artists.isEmpty || !profile.liked.isEmpty else {
            return cachedArtists?.artists ?? []
        }
        let known = Set(profile.artists.map { $0.lowercased() })

        let prompt = """
        You are a music discovery engine. The listener follows: \(profile.artists.joined(separator: ", ")). \
        Their liked songs: \(profile.liked.joined(separator: "; ")).
        Suggest 12 artists they would likely enjoy but probably do NOT know yet \
        (avoid these: \(profile.artists.joined(separator: ", "))).
        Reply ONLY with a JSON array of artist names: ["Artist", ...]. No prose.
        """

        guard let text = try? await client.complete(prompt),
              let names = parseNames(text), !names.isEmpty else {
            return cachedArtists?.artists ?? []
        }

        var resolved: [ArtistItem] = []
        var seen = Set<String>()
        for name in names where !known.contains(name.lowercased()) {
            if let artist = await resolveArtist(name), seen.insert(artist.name.lowercased()).inserted {
                resolved.append(artist)
            }
            if resolved.count >= 10 { break }
        }

        if !resolved.isEmpty {
            cachedArtists = (Date(), resolved)
            return resolved
        }
        return cachedArtists?.artists ?? []
    }

    // MARK: - Helpers

    private static func resolveArtist(_ name: String) async -> ArtistItem? {
        guard !name.isEmpty, let raw = try? await SearchService.shared.search(query: name) else { return nil }
        for section in SearchParser.parseSearchResults(from: raw) {
            for item in section.items {
                if case .artist(let artist) = item { return artist }
            }
        }
        return nil
    }

    private static func loadProfile() async -> (artists: [String], liked: [String]) {
        let artists = (try? await DatabaseService.shared.fetchArtists(limit: 12))?.map(\.name) ?? []
        let liked = (try? await DatabaseService.shared.fetchAllLikedSongs())?
            .prefix(20)
            .map { "\($0.title) — \($0.artistName ?? "")" } ?? []
        return (artists, liked)
    }

    private static func parseSuggestions(_ text: String) -> [(artist: String, title: String)]? {
        guard let jsonText = extractArray(from: text),
              let data = jsonText.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return array.compactMap { object in
            guard let artist = object["artist"] as? String,
                  let title = object["title"] as? String else { return nil }
            let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanArtist.isEmpty, !cleanTitle.isEmpty else { return nil }
            return (cleanArtist, cleanTitle)
        }
    }

    private static func parseNames(_ text: String) -> [String]? {
        guard let jsonText = extractArray(from: text),
              let data = jsonText.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return nil
        }
        return array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func extractArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start < end else { return nil }
        return String(text[start...end])
    }
}
