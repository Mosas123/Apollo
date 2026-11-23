import Foundation

@main
struct TropGlobalAudioSelectionPolicyChecks {
    static func main() {
        func item(
            _ title: String = "NORMAL", artist: String = "BTS",
            duration: Int = 198, album: String? = "ARIRANG",
            isStreamable: Bool = true
        ) -> MusicCatalogTrack {
            var track = MusicCatalogTrack(
                id: MusicCatalogID(source: .addon, rawValue: "sample-" + title),
                title: title, artist: artist, durationSeconds: duration,
                artworkURL: nil, permalinkURL: nil, isStreamable: isStreamable
            )
            track.albumTitle = album
            return track
        }
        func recording(_ album: String? = "ARIRANG", duration: Int? = nil)
            -> TropGlobalRecording {
            TropGlobalRecording(
                id: "public:test", title: "NORMAL", artist: "BTS",
                album: album, listenCount: 150, durationSeconds: duration
            )
        }

        let exact = item()
        precondition(TropGlobalAudioSelectionPolicy.bestCandidate(
            for: recording(), among: [exact]
        )?.id == exact.id)

        // Metadata with no run time can still play an album-confirmed,
        // exact-title and exact-artist track when the addon omits duration.
        let noTiming = item(duration: 0)
        precondition(TropGlobalAudioSelectionPolicy.bestCandidate(
            for: recording(), among: [noTiming]
        ) != nil)

        // Neither album nor duration: cannot prove release identity.
        precondition(TropGlobalAudioSelectionPolicy.bestCandidate(
            for: recording(nil), among: [item(duration: 0, album: nil)]
        ) == nil)
        precondition(TropGlobalAudioSelectionPolicy.bestCandidate(
            for: recording(), among: [item(album: "Different album")]
        ) == nil)
        precondition(TropGlobalAudioSelectionPolicy.bestCandidate(
            for: recording(), among: [item(artist: "Different Band")]
        ) == nil)
        precondition(TropGlobalAudioSelectionPolicy.bestCandidate(
            for: recording(), among: [item("NORMAL (Live)")]
        ) == nil)
        precondition(TropGlobalAudioSelectionPolicy.bestCandidate(
            for: recording(), among: [item(album: "Live from London")]
        ) == nil)
        precondition(TropGlobalAudioSelectionPolicy.bestCandidate(
            for: recording(), among: [item(isStreamable: false)]
        ) == nil)

        // Do not silently choose between versions with divergent durations.
        precondition(TropGlobalAudioSelectionPolicy.bestCandidate(
            for: recording(), among: [item(duration: 180), item(duration: 250)]
        ) == nil)

        // Known reference duration uses the strict Library-style match instead.
        precondition(TropGlobalAudioSelectionPolicy.bestCandidate(
            for: recording(duration: 200), among: [exact]
        ) == nil)
        print("Global one-tap audio matching policy checks passed")
    }
}
