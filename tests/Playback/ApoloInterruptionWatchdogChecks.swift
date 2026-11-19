import Foundation

@main
struct ApoloInterruptionWatchdogChecks {
    private static var checks = 0

    private static func expect(_ result: Bool, _ message: String) {
        precondition(result, message)
        checks += 1
    }

    private static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    static func main() {
        var initial = ApoloFiniteAudioWatchdog()
        expect(!initial.hasTimedOut(
            now: at(0), isInterrupted: false, interruptionEndedAt: nil
        ), "Initial load is allowed")
        expect(!initial.hasTimedOut(
            now: at(19.9), isInterrupted: false, interruptionEndedAt: nil
        ), "Initial load within 20 seconds is allowed")
        expect(initial.hasTimedOut(
            now: at(20.1), isInterrupted: false, interruptionEndedAt: nil
        ), "Permanently stalled initial load still falls back")

        initial.reset() // First playing happened: original loading deadline is obsolete.
        expect(!initial.hasTimedOut(
            now: at(100), isInterrupted: false, interruptionEndedAt: nil
        ), "A later buffering phase gets a fresh 20 seconds")
        expect(!initial.hasTimedOut(
            now: at(119.5), isInterrupted: false, interruptionEndedAt: nil
        ), "Short buffering does not fall back")
        expect(initial.hasTimedOut(
            now: at(120.5), isInterrupted: false, interruptionEndedAt: nil
        ), "Genuine buffering stall still falls back")

        var instagram = ApoloFiniteAudioWatchdog()
        expect(!instagram.hasTimedOut(
            now: at(0), isInterrupted: false, interruptionEndedAt: nil
        ), "Playback was already established")
        instagram.reset() // .playing
        expect(!instagram.hasTimedOut(
            now: at(45), isInterrupted: true, interruptionEndedAt: nil
        ), "Do not fall back while Instagram owns the audio session")
        expect(!instagram.hasTimedOut(
            now: at(90), isInterrupted: true, interruptionEndedAt: nil
        ), "A long iOS interruption is not a failed load")
        expect(!instagram.hasTimedOut(
            now: at(90.311), isInterrupted: false, interruptionEndedAt: at(90)
        ), "Exactly the Raindrops reproduction: 311ms after interruption ends")
        expect(!instagram.hasTimedOut(
            now: at(109), isInterrupted: false, interruptionEndedAt: at(90)
        ), "Allow the continuous post-interruption recovery window")
        expect(instagram.hasTimedOut(
            now: at(111), isInterrupted: false, interruptionEndedAt: at(90)
        ), "After 20s genuinely stuck, MPVKit remains the fallback")

        var suspended = ApoloFiniteAudioWatchdog()
        expect(!suspended.hasTimedOut(
            now: at(10), isInterrupted: false, interruptionEndedAt: nil
        ), "Pending phase starts")
        // Simulate main actor not being scheduled for the entire interruption.
        expect(!suspended.hasTimedOut(
            now: at(60.3), isInterrupted: false, interruptionEndedAt: at(60)
        ), "Interruption end timestamp protects suspended watchdog")
        expect(!suspended.hasTimedOut(
            now: at(79), isInterrupted: false, interruptionEndedAt: at(60)
        ), "Timer is measured from the end of iOS interruption")
        expect(suspended.hasTimedOut(
            now: at(81), isInterrupted: false, interruptionEndedAt: at(60)
        ), "Stall after returning to foreground can still fall back")

        var mixed = ApoloFiniteAudioWatchdog()
        expect(!mixed.hasTimedOut(
            now: at(0), isInterrupted: false, interruptionEndedAt: nil
        ), "Entered idle")
        expect(!mixed.hasTimedOut(
            now: at(10), isInterrupted: false, interruptionEndedAt: nil
        ), "Changed to loading; continuous pending phase not reset")
        expect(mixed.hasTimedOut(
            now: at(21), isInterrupted: false, interruptionEndedAt: nil
        ), "Alternating idle/loading cannot avoid timeout")
        mixed.reset() // .paused or .playing
        expect(!mixed.hasTimedOut(
            now: at(70), isInterrupted: false, interruptionEndedAt: nil
        ), "A fully recovered player starts a new pending phase")

        print("PASS: \(checks) Apolo audio interruption and recovery checks")
    }
}
