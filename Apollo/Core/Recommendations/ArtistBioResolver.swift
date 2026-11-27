import Foundation

/// Resolves an artist's birth date and origin from MusicBrainz (cached). Used
/// by the artist info sheet, since YouTube Music and iTunes don't expose them.
@MainActor
enum ArtistBioResolver {
    struct Bio: Equatable {
        let born: String?
        let from: String?
    }

    private static var cache: [String: Bio?] = [:]

    static func bio(for artist: String) async -> Bio? {
        let key = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        let bio = await fetch(artist)
        if cache.count >= 500, cache[key] == nil {
            for victim in Array(cache.keys.prefix(100)) {
                cache.removeValue(forKey: victim)
            }
        }
        cache[key] = bio
        return bio
    }

    private static func fetch(_ artist: String) async -> Bio? {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/artist/")
        components?.queryItems = [
            URLQueryItem(name: "query", value: "artist:\"\(artist)\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Apollo/1.0 (https://github.com/Mosas123/Apollo)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }

        struct Response: Decodable {
            struct Artist: Decodable {
                struct LifeSpan: Decodable { let begin: String? }
                struct Area: Decodable { let name: String? }
                let lifeSpan: LifeSpan?
                let area: Area?
                let country: String?

                enum CodingKeys: String, CodingKey {
                    case lifeSpan = "life-span"
                    case area
                    case country
                }
            }
            let artists: [Artist]?
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let match = decoded.artists?.first else { return nil }
        return Bio(born: formatDate(match.lifeSpan?.begin), from: match.area?.name ?? match.country)
    }

    private static func formatDate(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
}
