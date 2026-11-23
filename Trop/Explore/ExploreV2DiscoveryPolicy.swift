import Foundation

/// Foreground-only Explore suggestions from the user's own saved metadata.
/// No YouTube catalogue, ranking feed, autoplay or background bulk crawling.
enum ExploreV2DiscoveryPolicy {
    static let maximumSeedArtists = 6
    static let maximumAddonInstallations = 3
    static let resultsPerProvider = 12
    static let maximumVisibleTracks = 24

    static func artistSeeds(_ candidates: [String?]) -> [String] {
        var keys = Set<String>()
        var result: [String] = []
        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), trimmed.count >= 2, trimmed.count <= 120 else { continue }
            let key = normalize(trimmed)
            guard !key.isEmpty, keys.insert(key).inserted else { continue }
            result.append(trimmed)
            if result.count == maximumSeedArtists { break }
        }
        return result
    }

    /// Keep unrelated people with similarly named tracks out of this shelf.
    /// Collaboration credits may extend the chosen artist with a separator.
    static func matchesArtist(_ candidate: String, selected: String) -> Bool {
        let wanted = normalize(selected)
        let actual = normalize(candidate)
        guard wanted.count >= 2 else { return false }
        if actual == wanted { return true }
        return [",", " & ", " feat ", " featuring ", " x "].contains {
            actual.hasPrefix(wanted + $0)
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}
