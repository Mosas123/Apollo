import Foundation

/// Regression checks compile the exact Foundation-only policies used by the
/// iOS app, not copies of their production conditionals.
@main
struct PlaybackGuardChecks {
    static func main() {
        let segment = SponsorBlockSkipPolicy.shouldSkip
        precondition(
            !segment(0, 20, 0, false),
            "Disabled intro opt-in must prevent the startup skip"
        )
        precondition(
            segment(0, 20, 0, true),
            "Enabled intro opt-in should allow a short intro skip"
        )
        precondition(
            !segment(0, 30, 0, true),
            "Even an opted-in intro over 25 s must remain untouched"
        )
        precondition(
            !segment(0.2, 15, 0.2, false),
            "Near-zero intros must also respect the opt-in"
        )
        precondition(
            segment(10, 25, 12, false),
            "Mid-track nonmusic skipping remains available"
        )
        precondition(
            !segment(10, 25, 9.7, false),
            "Do not prefire beyond the 250 ms boundary"
        )
        precondition(
            !segment(10, 25, 24.2, false),
            "Do not seek in the last second of a segment"
        )
        precondition(
            !segment(.nan, 20, 1, true),
            "Malformed remote segments must not trigger a seek"
        )
        precondition(
            !segment(5, .infinity, 7, true),
            "Unbounded segment endpoints must be rejected"
        )
        precondition(PlaybackIntentGuard.owns(
            expectedGeneration: 4, expectedVideoId: "MONACO",
            generation: 4, videoId: "MONACO"
        ), "Current resolver may publish")
        precondition(!PlaybackIntentGuard.owns(
            expectedGeneration: 4, expectedVideoId: "MONACO",
            generation: 5, videoId: "NADIE SABE"
        ), "Old resolver must not auto-advance a new track")
        precondition(!PlaybackIntentGuard.owns(
            expectedGeneration: 4, expectedVideoId: "MONACO",
            generation: 6, videoId: "MONACO"
        ), "A -> B -> A must not revive stale work")
        precondition(!PlaybackIntentGuard.owns(
            expectedGeneration: 4, expectedVideoId: "MONACO",
            generation: 4, videoId: "NADIE SABE"
        ), "Same-generation wrong track cannot publish")
        precondition(!PlaybackIntentGuard.isLatest(
            serial: 12, latestSerial: 13
        ), "A superseded load must not publish the old quality badge")
        precondition(PlaybackIntentGuard.isLatest(
            serial: 13, latestSerial: 13
        ), "The active source request may publish")

        print("PASS: 15 playback startup/skip/ABA regression checks")
    }
}
