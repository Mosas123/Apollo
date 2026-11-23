import Foundation

/// A discovery result may not have a duration (ListenBrainz public charts).
/// Do not weaken the strict matching used for saved Library V2 aliases.
/// This policy only decides whether a temporary, user-tapped result has one
/// safe full-length studio-audio candidate.
enum TropGlobalAudioSelectionPolicy {
    static func bestCandidate(
        for recording: TropGlobalRecording,
        among reviews: [MusicCatalogTrack]
    ) -> MusicCatalogTrack? {
        // Known-duration recordings must use the existing strict exact matcher.
        guard (recording.durationSeconds ?? 0) <= 0 else { return nil }
        let safe = reviews.filter { track in
            guard track.isStreamable, track.durationSeconds > 0,
                  TextMatch.recordingsMatch(recording.title, track.title),
                  TextMatch.normalizeArtist(recording.artist)
                    == TextMatch.normalizeArtist(track.artist),
                  !TextMatch.normalizeArtist(track.artist).isEmpty
            else { return false }

            // Never silently substitute remix/live/acoustic or instrumental.
            let markers = TextMatch.versionMarkers(track.title)
            guard markers.isEmpty || markers == TextMatch.versionMarkers(recording.title) else {
                return false
            }
            let release = TextMatch.normalize(track.albumTitle ?? "")
            if ["live", "remix", "acoustic", "instrumental",
                "karaoke", "tribute", "bootleg", "demo"].contains(where: {
                release.split(separator: " ").contains(Substring($0))
            }) {
                return false
            }
            let expected = TextMatch.normalize(recording.album ?? "")
            return expected.isEmpty || release.isEmpty || expected == release
        }
        guard let first = safe.first else { return nil }
        // Different run times for an unknown recording may be different edits.
        // If providers disagree strongly, request explicit version review.
        guard safe.allSatisfy({
            abs($0.durationSeconds - first.durationSeconds) <= 15
        }) else { return nil }
        return first
    }
}
