import Foundation

/// Resolves an artist's genre through the same cached Apple/MusicBrainz
/// clients used by the catalogue enricher. No direct, uncached URLSession.
@MainActor
enum ArtistGenreResolver {
    private static var cache: [String: String?] = [:]

    static func genre(for artist: String) async -> String? {
        let key = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        let genre = await fetch(artist)
        if cache.count >= 500, cache[key] == nil {
            for victim in Array(cache.keys.prefix(100)) {
                cache.removeValue(forKey: victim)
            }
        }
        cache[key] = genre
        return genre
    }

    private static func fetch(_ artist: String) async -> String? {
        let items = (try? await AppleCatalogClient().search(
            term: artist,
            entity: .musicArtist,
            limit: 3
        )) ?? []
        let wanted = TextMatch.normalizeArtist(artist)
        if let match = items.first(where: {
            TextMatch.normalizeArtist($0.artistName ?? $0.title) == wanted
        }) ?? items.first,
           let genre = match.genre?.trimmingCharacters(in: .whitespacesAndNewlines),
           !genre.isEmpty {
            return genre
        }
        return await MusicBrainzClient().artistTags(name: artist, limit: 1).first
    }
}
