import Foundation

/// One genre/tag candidate with the weight MusicBrainz gave it. Kept free of
/// networking so tag selection can be tested deterministically.
struct MusicBrainzTagCandidate: Hashable, Sendable {
    let name: String
    let weight: Int
}

enum MusicBrainzTagPolicy {
    static let ignored: Set<String> = [
        "seen live", "favorite", "favourites", "spotify", "owned",
        "albums i own", "under 2000 listeners"
    ]

    /// Genres are stronger evidence than free-form tags. Sorting is stable by
    /// weight and then name, so the same response always produces the same
    /// station search terms.
    static func select(_ candidates: [MusicBrainzTagCandidate], limit: Int = 8) -> [String] {
        guard limit > 0 else { return [] }
        var best: [String: (name: String, weight: Int)] = [:]
        for candidate in candidates {
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard !ignored.contains(key) else { continue }
            if let existing = best[key] {
                best[key] = (existing.name, max(existing.weight, candidate.weight))
            } else {
                best[key] = (name, candidate.weight)
            }
        }
        return best.values
            .sorted {
                if $0.weight != $1.weight { return $0.weight > $1.weight }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0.name }
    }

    static func candidates(
        genres: [String],
        tags: [(name: String, count: Int?)]
    ) -> [MusicBrainzTagCandidate] {
        genres.map { MusicBrainzTagCandidate(name: $0, weight: 10) }
            + tags.map { MusicBrainzTagCandidate(name: $0.name, weight: $0.count ?? 0) }
    }
}
