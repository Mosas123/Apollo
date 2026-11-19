import Foundation

/// Bounds only the *current continuous* non-playing phase of an Apolo radio
/// stream. The lifetime of a successfully playing station is not a timeout.
///
/// The clock is shared across .loading/.idle/.failed so reconnect transitions
/// cannot reset the deadline indefinitely. A system audio interruption is not
/// a transport failure; a completed interruption starts a fresh grace window.
struct ApoloLiveRadioWatchdog {
    private(set) var pendingSince: Date?

    mutating func reset() {
        pendingSince = nil
    }

    /// The caller sets 35s for .failed and 40s for .loading/.idle.
    /// These are existing policy bounds, not an absolute station age.
    mutating func hasTimedOut(
        now: Date,
        timeout: TimeInterval,
        isInterrupted: Bool,
        interruptionEndedAt: Date?
    ) -> Bool {
        guard !isInterrupted else {
            reset()
            return false
        }

        let start = pendingSince ?? now
        // If the monitor was suspended during a system interruption, never
        // count time before the corresponding end notification against Apolo.
        let effectiveStart = max(start, interruptionEndedAt ?? start)
        pendingSince = effectiveStart
        return now.timeIntervalSince(effectiveStart) > timeout
    }
}
