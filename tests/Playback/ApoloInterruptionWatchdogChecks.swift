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

        // Radio previously used station age as the loading deadline. In
        // log(9), a healthy station playing for >40s entered .loading after
        // a video interruption and fell back to mpv in 186ms.
        var radio = ApoloLiveRadioWatchdog()
        expect(!radio.hasTimedOut(
            now: at(0), timeout: 40, isInterrupted: false, interruptionEndedAt: nil
        ), "Radio initial load starts fresh deadline")
        expect(!radio.hasTimedOut(
            now: at(39.9), timeout: 40, isInterrupted: false, interruptionEndedAt: nil
        ), "Initial radio loading gets its full 40-second allowance")
        expect(radio.hasTimedOut(
            now: at(40.1), timeout: 40, isInterrupted: false, interruptionEndedAt: nil
        ), "Real 40-second radio loading stall still falls back")

        radio.reset() // .playing after initial load
        expect(!radio.hasTimedOut(
            now: at(180), timeout: 40, isInterrupted: false, interruptionEndedAt: nil
        ), "Healthy station age must not immediately time out a new loading phase")
        expect(!radio.hasTimedOut(
            now: at(180.186), timeout: 40, isInterrupted: false, interruptionEndedAt: nil
        ), "Exactly the 186ms video interruption reproduction")
        radio.reset() // .playing again

        expect(!radio.hasTimedOut(
            now: at(250), timeout: 40, isInterrupted: true, interruptionEndedAt: nil
        ), "Do not count iOS video interruption against radio transport")
        expect(!radio.hasTimedOut(
            now: at(430), timeout: 40, isInterrupted: true, interruptionEndedAt: nil
        ), "Very long interruption must not trigger mpv")
        expect(!radio.hasTimedOut(
            now: at(430.186), timeout: 40, isInterrupted: false,
            interruptionEndedAt: at(430)
        ), "Return from video interruption gets fresh radio grace")
        expect(!radio.hasTimedOut(
            now: at(469), timeout: 40, isInterrupted: false,
            interruptionEndedAt: at(430)
        ), "Post-interruption recovery is not a station-age timeout")
        expect(radio.hasTimedOut(
            now: at(471), timeout: 40, isInterrupted: false,
            interruptionEndedAt: at(430)
        ), "Radio can still fall back after a genuine continuous stall")

        var radioSuspend = ApoloLiveRadioWatchdog()
        expect(!radioSuspend.hasTimedOut(
            now: at(10), timeout: 40, isInterrupted: false,
            interruptionEndedAt: nil
        ), "Radio pending time begins before app suspension")
        expect(!radioSuspend.hasTimedOut(
            now: at(501), timeout: 40, isInterrupted: false,
            interruptionEndedAt: at(500)
        ), "Late wake must use interruption end timestamp")
        expect(radioSuspend.hasTimedOut(
            now: at(541), timeout: 40, isInterrupted: false,
            interruptionEndedAt: at(500)
        ), "Radio remains bounded after wake")

        var reconnect = ApoloLiveRadioWatchdog()
        expect(!reconnect.hasTimedOut(
            now: at(0), timeout: 35, isInterrupted: false,
            interruptionEndedAt: nil
        ), "First failed state begins retry budget")
        expect(!reconnect.hasTimedOut(
            now: at(20), timeout: 40, isInterrupted: false,
            interruptionEndedAt: nil
        ), "Switch to loading does not reset shared pending phase")
        expect(reconnect.hasTimedOut(
            now: at(36), timeout: 35, isInterrupted: false,
            interruptionEndedAt: nil
        ), "Failed reconnect retains 35-second deadline across states")
        reconnect.reset() // .paused must clear pending deadline
        expect(!reconnect.hasTimedOut(
            now: at(120), timeout: 40, isInterrupted: false,
            interruptionEndedAt: nil
        ), "Explicit pause clears stale failure deadline")

        print("PASS: \(checks) Apolo audio interruption and recovery checks")
    }
}
