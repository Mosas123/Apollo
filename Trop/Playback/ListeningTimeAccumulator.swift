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
        defer {
            lastPosition = position
            lastUptime = uptime
        }
        guard let lastPosition, let lastUptime, uptime >= lastUptime else {
            return
        }
        let elapsed = uptime - lastUptime
        let advanced = position - lastPosition
        // A forward seek must not credit skipped music. Allow small precision/
        // scheduling drift between CoreMedia/MPV clocks and the system uptime.
        guard advanced > 0, advanced <= elapsed + 0.75 else { return }
        listenedSeconds += min(advanced, elapsed)
    }

    var listenedMilliseconds: Int64 {
        Int64((listenedSeconds * 1000).rounded(.down))
    }
}
