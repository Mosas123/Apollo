import Foundation

/// Pure decision for whether a SponsorBlock segment may seek during playback.
/// Intro skipping is a separate explicit user opt-in, independent of the
/// global "Skip Segments" toggle.
enum SponsorBlockSkipPolicy {
    /// SponsorBlock timestamps describe the *original YouTube video*, not a
    /// rematched studio recording. Fail closed for unknown provider names:
    /// legacy videoId equality does NOT prove the current audio came from YT.
    /// These identifiers come from ApolloTube's YouTubeClient.clientName.
    static func allowsSource(clientName: String) -> Bool {
        switch clientName.uppercased() {
        case "WEB", "WEB_REMIX", "IOS", "ANDROID", "ANDROID_VR",
             "TVHTML5", "TVHTML5_SIMPLY_EMBEDDED_PLAYER", "VISIONOS":
            return true
        default:
            return false
        }
    }

    static func shouldSkip(
        start: Double,
        end: Double,
        position: Double,
        skipIntroAtStart: Bool,
        allowAnyStartSegment: Bool = false
    ) -> Bool {
        guard start.isFinite, end.isFinite, position.isFinite,
              start >= 0, end > start else { return false }
        if start < 0.5 {
            // Music intro boundaries can be inaccurate. Never skip these
            // without consent, and cap an opted-in intro at 25 seconds.
            // A podcast sponsor may legitimately start at 0 and be longer.
            if !allowAnyStartSegment {
                guard skipIntroAtStart, end <= 25 else { return false }
            }
        }
        return position >= start - 0.25 && position < end - 1
    }
}
