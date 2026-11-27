import Foundation

/// Bounds a *continuous* pending phase of finite Apolo audio.
///
/// The startup deadline must never be reused after playback has succeeded.
/// When iOS interrupts another app's audio (for example Instagram), time
/// spent inside the system interruption must not count as a failed load.
struct ApoloFiniteAudioWatchdog {
    private(set) var pendingSince: Date?
    let timeout: TimeInterval

    init(timeout: TimeInterval = 20) {
        self.timeout = timeout
    }

    mutating func reset() {
        pendingSince = nil
    }

    /// Call for both .loading and .idle, which represent the same pending
    /// recovery phase. Other states clear the phase via reset().
    mutating func hasTimedOut(
        now: Date,
        isInterrupted: Bool,
        interruptionEndedAt: Date?
    ) -> Bool {
        guard !isInterrupted else {
            reset()
            return false
        }

        // A suspended app may not poll the backend while Instagram owns the
        // audio session. A notification timestamp makes the deadline fresh
        // even when the first poll runs *after* the interruption has ended.
        let start = pendingSince ?? now
        let effectiveStart = max(start, interruptionEndedAt ?? start)
        pendingSince = effectiveStart
        return now.timeIntervalSince(effectiveStart) > timeout
    }
}
