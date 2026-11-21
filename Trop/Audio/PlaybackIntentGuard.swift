import Foundation

/// Pure ownership fence for asynchronous playback work. Track identity
/// alone is insufficient: A -> B -> A is an ABA transition, so the monotonic
/// intent generation must match as well.
enum PlaybackIntentGuard {
    static func owns(
        expectedGeneration: Int,
        expectedVideoId: String,
        generation: Int,
        videoId: String?
    ) -> Bool {
        expectedGeneration == generation && expectedVideoId == videoId
    }

    static func isLatest(
        serial: UInt64,
        latestSerial: UInt64
    ) -> Bool {
        serial == latestSerial
    }
}


/// Manual queue navigation is a fresh playback intent, even while a previous
/// song's source is still resolving. Generation + track ownership fences
/// prevent the stale resolver from publishing after a skip. Only an automatic
/// EOF advance must wait for the active resolution to settle.
enum QueueAdvancePolicy {
    static func allowsNext(automatic: Bool, isResolvingNext: Bool) -> Bool {
        !automatic || !isResolvingNext
    }
}


/// A pause belongs to a playback selection, not to an audio backend.
///
/// A new *user selection* may begin playing after an older selection was
/// paused. A delayed load, quality switch or Apolo -> mpv fallback for the
/// SAME selection must never turn an explicit Pause into Play.
enum PlaybackPausePolicy {
    /// While Next/Previous resolves, the backend state can still belong to the
    /// previous track. The button reflects the new selection's play intent,
    /// so a tap must invert that intent instead of the stale backend state.
    static func shouldPauseOnToggle(
        isResolvingSelection: Bool,
        selectionWantsPlayback: Bool,
        backendReportsPlaying: Bool
    ) -> Bool {
        isResolvingSelection ? selectionWantsPlayback : backendReportsPlaying
    }

    static func shouldPlay(
        generation: Int,
        explicitlyPausedGeneration: Int?,
        desiredPlaying: Bool,
        isNewSelection: Bool,
        isEngineFallback: Bool
    ) -> Bool {
        if explicitlyPausedGeneration == generation { return false }
        if isEngineFallback { return desiredPlaying }
        return isNewSelection || desiredPlaying
    }

    static func shouldAdvanceAutomatically(
        generation: Int,
        explicitlyPausedGeneration: Int?,
        desiredPlaying: Bool
    ) -> Bool {
        desiredPlaying && explicitlyPausedGeneration != generation
    }

    /// An intentionally paused decoder is not stalled. Re-start the timeout
    /// budget only after the user asks the backend to play again.
    static func watchdogIsSuspended(
        desiredPlaying: Bool,
        audioInterruptionActive: Bool
    ) -> Bool {
        !desiredPlaying || audioInterruptionActive
    }
}


/// Diagnostic classification only: never changes EOF handling or the queue.
/// Not every reported duration is exact; require both a meaningful absolute
/// and relative gap before flagging a suspicious early finish in device logs.
enum PlaybackEndEvidence {
    static func isMateriallyEarly(
        decoderPosition: TimeInterval,
        expectedDuration: TimeInterval
    ) -> Bool {
        guard decoderPosition.isFinite,
              expectedDuration.isFinite,
              decoderPosition >= 0,
              expectedDuration >= 30 else { return false }
        let missing = expectedDuration - decoderPosition
        return missing >= 8 && missing / expectedDuration >= 0.05
    }
}


/// A deferred Play belongs to the interrupted selection, not to whichever
/// track happens to be current when iOS eventually allows session activation.
/// Explicit Pause, a changed selection, or another active interruption wins.
enum AudioSessionResumePolicy {
    static func shouldRetry(
        pendingVideoId: String?,
        pendingGeneration: Int,
        currentVideoId: String?,
        currentGeneration: Int,
        desiredPlaying: Bool,
        interruptionActive: Bool,
        explicitlyPaused: Bool
    ) -> Bool {
        pendingVideoId == currentVideoId
            && pendingGeneration == currentGeneration
            && desiredPlaying
            && !interruptionActive
            && !explicitlyPaused
    }
}
