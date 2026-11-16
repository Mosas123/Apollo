import Foundation

/// Resolves an artist's genre from iTunes (cached per artist). YouTube Music
/// does not expose it in the artist header, and it powers the info sheet chip.
@MainActor
enum ArtistGenreResolver {
    private static var cache: [String: String?] = [:]

    static func genre(for artist: String) async -> String? {
        let key = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        let genre = await fetch(artist)
        cache[key] = genre
        return genre
    }

    private static func fetch(_ artist: String) async -> String? {
        if let genre = await iTunesGenre(artist, entity: "musicArtist") { return genre }
        return await iTunesGenre(artist, entity: "song")
    }

    private static func iTunesGenre(_ artist: String, entity: String) async -> String? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: artist),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "attribute", value: "artistTerm"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }

        struct Response: Decodable {
            struct Result: Decodable { let primaryGenreName: String? }
            let results: [Result]?
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let genre = decoded.results?.first?.primaryGenreName else { return nil }
        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
