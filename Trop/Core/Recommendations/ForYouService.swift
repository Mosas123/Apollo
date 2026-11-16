import Foundation

/// "For You": the AI suggests songs from the user's listening profile, and each
/// suggestion is validated against YouTube Music before it's shown — the same
/// pattern Nuvio uses with TMDB, adapted to music. Cached and rebuilt lazily.
@MainActor
enum ForYouService {
    private static var cached: (date: Date, songs: [SongItem])?
    private static let ttl: TimeInterval = 60 * 60 * 6

    static func musicSongs(force: Bool = false) async -> [SongItem] {
        if !force, let cached, Date().timeIntervalSince(cached.date) < ttl {
            return cached.songs
        }
        guard let client = AIProviderClient.configured() else {
            return cached?.songs ?? []
        }

        let artists = (try? await DatabaseService.shared.fetchArtists(limit: 12))?.map(\.name) ?? []
        let liked = (try? await DatabaseService.shared.fetchAllLikedSongs())?
            .prefix(20)
            .map { "\($0.title) — \($0.artistName ?? "")" } ?? []
        guard !artists.isEmpty || !liked.isEmpty else {
            return cached?.songs ?? []
        }

        let prompt = """
        You are a music recommendation engine. The listener follows these artists: \
        \(artists.joined(separator: ", ")). Their liked songs: \(liked.joined(separator: "; ")).
        Recommend 20 songs they likely haven't heard, mixing familiar artists with closely related ones.
        Reply ONLY with a JSON array of objects: [{"artist":"...","title":"..."}]. No prose.
        """

        guard let text = try? await client.complete(prompt),
              let suggestions = parseSuggestions(text), !suggestions.isEmpty else {
            return cached?.songs ?? []
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
            cached = (Date(), songs)
            return songs
        }
        return cached?.songs ?? []
    }

    private static func parseSuggestions(_ text: String) -> [(artist: String, title: String)]? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start < end else { return nil }
        let jsonText = String(text[start...end])
        guard let data = jsonText.data(using: .utf8),
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
}
