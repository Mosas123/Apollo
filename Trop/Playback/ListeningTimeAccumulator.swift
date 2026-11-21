import Foundation

/// Accumulates time from the media clock, not wall-clock time since selection.
///
/// A decoder's clock does not advance during an ordinary Pause or interruption,
/// so those periods cannot inflate listening history. A seek is a discontinuity,
/// not listening: reject jumps that exceed the monotonic time elapsed between
/// samples. Never infer audio was heard from a Play button or a media length.
struct ListeningTimeAccumulator {
    private(set) var listenedSeconds: TimeInterval = 0
    private var lastPosition: TimeInterval?
    private var lastUptime: TimeInterval?

    mutating func observe(position: TimeInterval, uptime: TimeInterval) {
        guard position.isFinite, position >= 0,
              uptime.isFinite, uptime >= 0 else { return }
        guard let previousPosition = lastPosition, let previousUptime = lastUptime else {
            lastPosition = position
            lastUptime = uptime
            return
        }
        // Concurrent sampler callbacks can finish out of order: older samples
        // must not rewind the baseline or cause duplicate credited audio.
        guard uptime >= previousUptime else { return }
        defer {
            lastPosition = position
            lastUptime = uptime
        }
        let elapsed = uptime - previousUptime
        let advanced = position - previousPosition
        // A forward seek must not credit skipped music. Allow small precision/
        // scheduling drift between CoreMedia/MPV clocks and the system uptime.
        guard advanced > 0, advanced <= elapsed + 0.75 else { return }
        listenedSeconds += min(advanced, elapsed)
    }

    var listenedMilliseconds: Int64 {
        Int64((listenedSeconds * 1000).rounded(.down))
    }
}
