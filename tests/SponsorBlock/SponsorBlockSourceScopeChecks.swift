import Foundation

@main
struct SponsorBlockSourceScopeChecks {
    static func main() {
        for native in [
            "WEB", "WEB_REMIX", "IOS", "ANDROID",
            "ANDROID_VR", "TVHTML5",
            "TVHTML5_SIMPLY_EMBEDDED_PLAYER", "VISIONOS"
        ] {
            precondition(SponsorBlockSkipPolicy.allowsSource(clientName: native))
        }

        for external in [
            "addon", "local", "qobuz", "audius", "jiosaavn",
            "addon-atmos", "addon-cd", "unknown", ""
        ] {
            precondition(
                !SponsorBlockSkipPolicy.allowsSource(clientName: external),
                "A YouTube videoId must not license a skip on third-party audio"
            )
        }

        // The old policy would have skipped into a 186.641-second VIDEO
        // segment at media position ~162, even on a 183.685-second FLAC.
        // The new provenance check makes that skip impossible on addons.
        let videoSegmentWouldSkip = SponsorBlockSkipPolicy.shouldSkip(
            start: 161.8, end: 186.641, position: 162.5,
            skipIntroAtStart: false
        )
        precondition(videoSegmentWouldSkip)
        precondition(!SponsorBlockSkipPolicy.allowsSource(clientName: "addon"))

        // Real YouTube audio of the original video keeps its opt-in behavior.
        precondition(SponsorBlockSkipPolicy.allowsSource(clientName: "IOS"))
        precondition(!SponsorBlockSkipPolicy.shouldSkip(
            start: 0, end: 10, position: 1, skipIntroAtStart: false
        ))
        precondition(SponsorBlockSkipPolicy.shouldSkip(
            start: 0, end: 10, position: 1, skipIntroAtStart: true
        ))
        precondition(!SponsorBlockSkipPolicy.shouldSkip(
            start: 50, end: 50, position: 50, skipIntroAtStart: true
        ))
        print("SponsorBlock source provenance scope checks passed")
    }
}
