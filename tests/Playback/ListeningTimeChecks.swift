import Foundation

/// Run against the actual production accumulator from macOS CI using swiftc.
enum ListeningTimeChecks {
    static func run() {
        var clock = ListeningTimeAccumulator()
        clock.observe(position: 0, uptime: 100)
        clock.observe(position: 5, uptime: 105)
        precondition(clock.listenedMilliseconds == 5_000, "Playing advances listening time")

        // Device case: user paused immediately, then remained paused for ~90 s.
        clock.observe(position: 5, uptime: 195)
        precondition(clock.listenedMilliseconds == 5_000, "Pause must not count")

        clock.observe(position: 8, uptime: 198)
        precondition(clock.listenedMilliseconds == 8_000, "Resume accumulates new audio only")

        clock.observe(position: 108, uptime: 199)
        precondition(clock.listenedMilliseconds == 8_000, "Forward seek must not count skipped audio")
        clock.observe(position: 112, uptime: 203)
        precondition(clock.listenedMilliseconds == 12_000, "Audio after a seek still counts")

        clock.observe(position: 2, uptime: 204)
        precondition(clock.listenedMilliseconds == 12_000, "Backward seek does not subtract history")
        clock.observe(position: 6, uptime: 208)
        precondition(clock.listenedMilliseconds == 16_000, "Replayed audio counts again")

        // Clock is monotonic even during user-initiated session interruptions.
        clock.observe(position: 6, uptime: 268)
        precondition(clock.listenedMilliseconds == 16_000, "Interruption must not count")
        clock.observe(position: 20, uptime: 282)
        precondition(clock.listenedMilliseconds == 30_000, "Thirty real seconds reach history threshold")

        clock.observe(position: .nan, uptime: 283)
        clock.observe(position: .infinity, uptime: 284)
        precondition(clock.listenedMilliseconds == 30_000, "Invalid decoder clocks cannot corrupt time")

        var offset = ListeningTimeAccumulator()
        offset.observe(position: 87, uptime: 100)
        offset.observe(position: 90, uptime: 103)
        precondition(offset.listenedMilliseconds == 3_000, "Resuming from 87s does not credit previous music")

        print("PASS: 11 listening-time, pause, seek, interruption and resume checks")
    }
}
