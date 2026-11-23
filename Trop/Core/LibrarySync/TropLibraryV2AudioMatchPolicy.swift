import Foundation

/// A recording's title/artist/duration are discovery clues, NEVER permission
/// to replace its Trop UUID or play an unverified lookalike. The result must
/// come from an explicitly enabled, full-track audio provider.
enum TropLibraryV2AudioMatchPolicy {
    static func alias(for track: MusicCatalogTrack) -> TropLibraryV2SourceAlias? {
        switch track.id.source {
        case .audius, .qobuz, .jiosaavn, .addon:
            return try? TropLibraryV2SourceAlias(
                provider: track.id.source.rawValue,
                externalID: track.id.rawValue
            )
        default:
            return nil
        }
    }

    static func accepts(
        title: String,
        artist: String?,
        durationSeconds: Int,
        track: MusicCatalogTrack,
        requiresLossless: Bool
    ) -> Bool {
        guard track.isStreamable, alias(for: track) != nil,
              let artist, !artist.isEmpty,
              (!requiresLossless || (track.id.source != .audius
                                     && track.id.source != .jiosaavn)) else {
            return false
        }
        return TextMatch.verifiedAudioSource(
            wantedTitle: title,
            wantedArtist: artist,
            wantedDuration: durationSeconds,
            candidateTitle: track.title,
            candidateArtist: track.artist,
            candidateDuration: track.durationSeconds
        )
    }
}
