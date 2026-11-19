import Foundation

/// Pure decision for whether a SponsorBlock segment may seek during playback.
/// Intro skipping is a separate explicit user opt-in, independent of the
/// global "Skip Segments" toggle.
enum SponsorBlockSkipPolicy {
    static func shouldSkip(
        start: Double,
        end: Double,
        position: Double,
        skipIntroAtStart: Bool
    ) -> Bool {
        guard start.isFinite, end.isFinite, position.isFinite,
              start >= 0, end > start else { return false }
        if start < 0.5 {
            // Music intro boundaries can be inaccurate. Never skip these
            // without consent, and cap an opted-in intro at 25 seconds.
            guard skipIntroAtStart, end <= 25 else { return false }
        }
        return position >= start - 0.25 && position < end - 1
    }
}
