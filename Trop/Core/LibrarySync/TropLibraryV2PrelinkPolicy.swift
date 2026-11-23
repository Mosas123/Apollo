import Foundation

/// Work limits for metadata-only prelinks in saved Library V2 recordings.
/// These are not a Home feed cache or a promise that a stream is playable.
enum TropLibraryV2PrelinkPolicy {
    static let visibleLibraryBudget = 6
    static let maximumQueuedRecordings = 16
    static let maximumIndependentAliases = 3
    static let maximumLinksPerPass = 2
    static let retryInterval: TimeInterval = 30 * 60

    static func hasSufficientMetadata(
        title: String, artist: String?, durationSeconds: Int
    ) -> Bool {
        guard let artist else { return false }
        return durationSeconds >= 30
            && TextMatch.normalizeTitle(title).count >= 2
            && !TextMatch.normalizeArtist(artist).isEmpty
    }

    /// Provider search results are not stream/codec guarantees.
    /// Select *only* strict exact editions; review suggestions never enter
    /// this path, even when the title, artist or cover look familiar.
    static func eligibleNewLinks(
        title: String,
        artist: String?,
        durationSeconds: Int,
        existingAliases: [TropLibraryV2SourceAlias],
        candidates: [MusicCatalogTrack]
    ) -> [MusicCatalogTrack] {
        guard hasSufficientMetadata(
            title: title, artist: artist, durationSeconds: durationSeconds
        ) else { return [] }

        let independentProviders: Set<String> = [
            "addon", "qobuz", "audius", "jiosaavn"
        ]
        var keys = Set(
            existingAliases.map { "\($0.provider):\($0.externalID)" }
        )
        var perProvider: [String: Int] = [:]
        let existing = existingAliases.filter {
            independentProviders.contains($0.provider)
        }
        for alias in existing {
            perProvider[alias.provider, default: 0] += 1
        }
        let slots = min(
            maximumLinksPerPass,
            max(0, maximumIndependentAliases - existing.count)
        )
        guard slots > 0 else { return [] }

        var matches: [MusicCatalogTrack] = []
        for candidate in candidates {
            guard matches.count < slots else { break }
            guard TropMatchCandidatePolicy.classify(
                title: title, artist: artist,
                durationSeconds: durationSeconds, track: candidate,
                requiresLossless: false
            ) == .exact,
                  let alias = TropLibraryV2AudioMatchPolicy.alias(
                    for: candidate
                  ) else { continue }
            let key = "\(alias.provider):\(alias.externalID)"
            guard !keys.contains(key) else { continue }

            // Multiple addon installations may provide separate verified
            // recordings. Avoid unbounded duplicate searches for one provider.
            let providerCap = alias.provider == "addon" ? 2 : 1
            guard perProvider[alias.provider, default: 0] < providerCap else {
                continue
            }
            matches.append(candidate)
            keys.insert(key)
            perProvider[alias.provider, default: 0] += 1
        }
        return matches
    }
}
