import Foundation

/// AI recommendations: the model suggests from the listener's profile and each
/// suggestion is validated against YouTube Music before it's shown — the same
/// pattern Nuvio uses with TMDB, adapted to music. Two separate shelves:
/// songs ("For You") and new artists ("Artistas para ti"). Cached, built lazily.
@MainActor
enum ForYouService {
    private static var cachedSongs: (date: Date, songs: [SongItem])?
    private static var cachedArtists: (date: Date, artists: [ArtistItem])?
    private static var cachedPodcasts: (date: Date, items: [YTItem])?
    private static var cachedProfile: (date: Date, artists: [String], liked: [String], genres: [String])?
    private static let profileTTL: TimeInterval = 60
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

        let genreNote = profile.genres.isEmpty ? "" : " Genres they enjoy: \(profile.genres.joined(separator: ", "))."
        let prompt = """
        You are a music recommendation engine. The listener follows these artists: \
        \(profile.artists.joined(separator: ", ")).\(genreNote) Their liked songs: \(profile.liked.joined(separator: "; ")).
        Recommend 20 songs they likely haven't heard, mixing familiar artists with closely related ones.
        Reply ONLY with a JSON array of objects: [{"artist":"...","title":"..."}]. No prose.
        """

        guard let text = try? await client.complete(prompt),
              let suggestions = parseSuggestions(text), !suggestions.isEmpty else {
            return cachedSongs?.songs ?? []
        }

        var songs: [SongItem] = []
        var seen = Set<String>()
        let batchSize = 4
        var start = 0
        while start < suggestions.count, songs.count < 15 {
            let end = min(start + batchSize, suggestions.count)
            let batch = suggestions[start..<end]
            let resolved = await withTaskGroup(of: SongItem?.self) { group -> [SongItem] in
                for suggestion in batch {
                    let artist = suggestion.artist
                    let title = suggestion.title
                    group.addTask { await resolveSuggestion(artist: artist, title: title) }
                }
                var out: [SongItem] = []
                for await song in group {
                    if let song { out.append(song) }
                }
                return out
            }
            for song in resolved {
                guard seen.insert(song.videoId).inserted else { continue }
                songs.append(song)
                if songs.count >= 15 { break }
            }
            start = end
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

        let genreNote = profile.genres.isEmpty ? "" : " Genres they enjoy: \(profile.genres.joined(separator: ", "))."
        let prompt = """
        You are a music discovery engine. The listener follows: \(profile.artists.joined(separator: ", ")).\(genreNote) \
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

    // MARK: - Podcasts

    static func podcasts(force: Bool = false) async -> [YTItem] {
        if !force, let cached = cachedPodcasts, Date().timeIntervalSince(cached.date) < ttl {
            return cached.items
        }
        guard let client = AIProviderClient.configured() else {
            return cachedPodcasts?.items ?? []
        }

        let profile = await loadProfile()
        guard !profile.artists.isEmpty || !profile.liked.isEmpty else {
            return cachedPodcasts?.items ?? []
        }

        let genreNote = profile.genres.isEmpty ? "" : " Genres they enjoy: \(profile.genres.joined(separator: ", "))."
        let prompt = """
        You are a podcast discovery engine. The listener follows: \(profile.artists.prefix(6).joined(separator: ", ")).\(genreNote)
        Suggest 10 podcasts they might enjoy, spanning their interests. Reply ONLY with a JSON array of podcast names: ["Podcast", ...]. No prose.
        """

        guard let text = try? await client.complete(prompt),
              let names = parseNames(text), !names.isEmpty else {
            return cachedPodcasts?.items ?? []
        }

        var items: [YTItem] = []
        var seen = Set<String>()
        for name in names {
            guard let raw = try? await SearchService.shared.search(query: name) else { continue }
            let episode = SearchParser.parseSearchResults(from: raw)
                .flatMap(\.items)
                .compactMap { item -> EpisodeItem? in
                    if case .episode(let episode) = item { return episode }
                    return nil
                }
                .first
            if let episode, seen.insert(episode.videoId).inserted {
                items.append(.episode(episode))
            }
            if items.count >= 8 { break }
        }

        if !items.isEmpty {
            cachedPodcasts = (Date(), items)
            return items
        }
        return cachedPodcasts?.items ?? []
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

    private static func loadProfile() async -> (artists: [String], liked: [String], genres: [String]) {
        if let cached = cachedProfile, Date().timeIntervalSince(cached.date) < profileTTL {
            return (cached.artists, cached.liked, cached.genres)
        }
        var artists = (try? await DatabaseService.shared.fetchArtists(limit: 12))?.map(\.name) ?? []
        for artist in TasteProfileStore.shared.topArtists(limit: 8) where !artists.contains(artist) {
            artists.append(artist)
        }
        let liked = (try? await DatabaseService.shared.fetchAllLikedSongs())?
            .prefix(20)
            .map { "\($0.title) — \($0.artistName ?? "")" } ?? []
        let profile = (artists, liked, TasteProfileStore.shared.topGenres(limit: 5))
        cachedProfile = (Date(), profile.0, profile.1, profile.2)
        return profile
    }

    private static func resolveSuggestion(artist: String, title: String) async -> SongItem? {
        let query = "\(artist) \(title)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let raw = try? await SearchService.shared.search(query: query) else { return nil }
        return SearchParser.parseSearchResults(from: raw)
            .first(where: { $0.title == "Songs" })?
            .items
            .compactMap { item -> SongItem? in
                if case .song(let song) = item { return song }
                return nil
            }
            .first
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
