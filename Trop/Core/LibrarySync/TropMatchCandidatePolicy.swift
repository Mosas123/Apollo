import Foundation

/// Trop Match classifies audio candidates independently from playback.
/// A "review" suggestion must never become a source alias automatically.
enum TropMatchCandidateKind: Equatable {
    case exact
    case review
    case unrelated
}

enum TropMatchCandidatePolicy {
    /// A confirmed match needs same title, performer, edition and supported
    /// duration. Title/duration alone do not prove a mix is identical, so
    /// suspect release titles always require the user's decision.
    static func classify(
        title: String,
        artist: String?,
        durationSeconds: Int,
        track: MusicCatalogTrack,
        requiresLossless: Bool
    ) -> TropMatchCandidateKind {
        guard let artist,
              !TextMatch.normalizeArtist(artist).isEmpty,
              track.isStreamable,
              TropLibraryV2AudioMatchPolicy.alias(for: track) != nil,
              (!requiresLossless || (track.id.source != .audius
                                     && track.id.source != .jiosaavn)),
              TextMatch.normalizeArtist(artist) == TextMatch.normalizeArtist(track.artist)
        else { return .unrelated }

        // Remove edition markers for *suggestion* discovery only. The exact
        // match path below still preserves live/remix/instrumental differences.
        let savedTitle = TextMatch.normalizeTitle(title)
        let candidateTitle = TextMatch.normalizeTitle(track.title)
        guard !savedTitle.isEmpty, savedTitle == candidateTitle else {
            return .unrelated
        }
        let unknownDuration = durationSeconds <= 0 || track.durationSeconds <= 0
        if !unknownDuration {
            let gap = abs(durationSeconds - track.durationSeconds)
            guard gap <= max(30, durationSeconds / 5) else {
                return .unrelated
            }
        }
        if suspectRelease(track.albumTitle),
           !suspectRelease(title) {
            return .review
        }
        if TextMatch.verifiedAudioSource(
            wantedTitle: title,
            wantedArtist: artist,
            wantedDuration: durationSeconds,
            candidateTitle: track.title,
            candidateArtist: track.artist,
            candidateDuration: track.durationSeconds
        ) {
            return .exact
        }
        return .review
    }

    private static func suspectRelease(_ release: String?) -> Bool {
        guard let release, !release.isEmpty else { return false }
        let normalized = TextMatch.normalize(release)
        if normalized.contains("en vivo") || normalized.contains("ao vivo") {
            return true
        }
        let words = Set(normalized.split(separator: " ").map(String.init))
        return !words.isDisjoint(with: [
            "live", "remix", "acoustic", "instrumental", "karaoke",
            "tribute", "bootleg", "demo"
        ])
    }
}

struct TropMatchSearchResult: Sendable {
    let exact: [MusicCatalogTrack]
    let review: [MusicCatalogTrack]
}
