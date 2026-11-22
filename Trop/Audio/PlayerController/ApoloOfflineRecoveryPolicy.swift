import Foundation

/// Transport outages are not decoder incompatibilities. A finite HTTP track
/// must retain Apolo ownership until connectivity returns or the user changes
/// selection. Live radio has separate bounded reconnect semantics.
enum ApoloOfflineRecoveryPolicy {
    static func shouldHold(
        isFiniteAudio: Bool,
        isHTTPSource: Bool,
        networkUnavailable: Bool
    ) -> Bool {
        isFiniteAudio && isHTTPSource && networkUnavailable
    }

    /// Never restart audio that belongs to an older song, an older renderer,
    /// a manually paused selection, or an interrupted audio session.
    static func mayResume(
        sameSelection: Bool,
        sameEngineGeneration: Bool,
        networkAvailable: Bool,
        desiredPlaying: Bool,
        explicitlyPaused: Bool,
        audioInterrupted: Bool,
        audioActivationPending: Bool
    ) -> Bool {
        sameSelection
            && sameEngineGeneration
            && networkAvailable
            && desiredPlaying
            && !explicitlyPaused
            && !audioInterrupted
            && !audioActivationPending
    }
}
