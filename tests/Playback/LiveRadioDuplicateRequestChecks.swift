import Foundation

@main
struct LiveRadioDuplicateRequestChecks {
    private static var checks = 0

    private static func expect(_ value: Bool, _ message: String) {
        precondition(value, message)
        checks += 1
    }

    static func main() {
        typealias Session = LiveRadioDuplicateRequestPolicy.ActiveSession
        let rtlID = "radio:042d3140-227c-4fac-9387-4903b692d5f2"
        let otherID = "radio:other-station"
        let rtlURL = URL(string: "https://radio.example/rtl/live.m3u8?token=abc")!
        let alternateURL = URL(string: "https://radio.example/rtl/live.m3u8?token=def")!

        let baseline = Session(
            stationID: rtlID,
            streamURL: rtlURL,
            apoloActive: true,
            apoloRadioEnabled: true,
            isLoadingOrPlaying: true,
            desiredPlaying: true,
            isInterrupted: false
        )

        func ignored(
            _ session: Session,
            requestedID: String? = nil,
            requestedURL: URL? = nil,
            bypassApolo: Bool = false
        ) -> Bool {
            LiveRadioDuplicateRequestPolicy.shouldSuppress(
                requestedID: requestedID ?? rtlID,
                requestedURL: requestedURL ?? rtlURL,
                bypassApolo: bypassApolo,
                active: session
            )
        }

        // Regression for log(10): identical RTL HLS starts 1.231s apart.
        expect(ignored(baseline), "Second RTL request while loading or playing is ignored")

        var session = baseline
        session = Session(
            stationID: baseline.stationID,
            streamURL: baseline.streamURL,
            apoloActive: false,
            apoloRadioEnabled: true,
            isLoadingOrPlaying: true,
            desiredPlaying: true,
            isInterrupted: false
        )
        expect(!ignored(session), "First station load proceeds")
        expect(!ignored(baseline, requestedID: otherID), "Selecting a new station proceeds")
        expect(!ignored(baseline, requestedURL: alternateURL), "Refreshing expired HLS URL proceeds")
        expect(!ignored(baseline, bypassApolo: true), "Explicit MPV fallback is not blocked")
        expect(!ignored(baseline, requestedID: "youtube-song"), "Music must not be suppressed")

        // Mutable copies keep the test independent of AVFoundation and allow
        // each policy condition to be isolated without a giant parameter list.
        session = baseline
        session.stationID = otherID
        expect(!ignored(session), "Current station ID must match")
        session = baseline
        session.streamURL = nil
        expect(!ignored(session), "Unknown current URL must not suppress")
        session = baseline
        session.streamURL = alternateURL
        expect(!ignored(session), "New current stream must not suppress")
        session = baseline
        session.apoloRadioEnabled = false
        expect(!ignored(session), "Disabling radio beta allows engine switch")
        session = baseline
        session.isLoadingOrPlaying = false
        expect(!ignored(session), "Paused/idle/failed phase permits explicit retry")
        session = baseline
        session.desiredPlaying = false
        expect(!ignored(session), "User pause allows explicit restart")
        session = baseline
        session.isInterrupted = true
        expect(!ignored(session), "User selection during interruption is not dropped")
        session = baseline
        session.apoloActive = false
        expect(!ignored(session), "MPV active path must be unaffected")
        let differentStream = URL(string: "https://radio.example/other.m3u8")!
        expect(!ignored(baseline, requestedURL: differentStream), "Different stream URL under same ID must proceed")

        // Simulated app behavior: same station while playing keeps the engine,
        // but an explicit retry after .failed remains possible.
        expect(ignored(baseline), "Playing state still ignores repeat")
        session = baseline
        session.isLoadingOrPlaying = false
        expect(!ignored(session), "Failed state permits reloading the same RTL HLS")

        print("PASS: \(checks) live radio duplicate-request policy checks")
    }
}
