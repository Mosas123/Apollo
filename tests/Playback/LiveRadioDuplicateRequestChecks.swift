import Foundation

@main
struct LiveRadioDuplicateRequestChecks {
    private static var checks = 0

    private static func expect(_ value: Bool, _ message: String) {
        precondition(value, message)
        checks += 1
    }

    static func main() {
        let rtlID = "radio:042d3140-227c-4fac-9387-4903b692d5f2"
        let otherID = "radio:other-station"
        let rtlURL = URL(string: "https://radio.example/rtl/live.m3u8?token=abc")!
        let alternateURL = URL(string: "https://radio.example/rtl/live.m3u8?token=def")!

        func ignored(
            requestedID: String? = rtlID,
            requestedURL: URL = rtlURL,
            currentID: String? = rtlID,
            currentURL: URL? = rtlURL,
            apoloActive: Bool = true,
            apoloRadioEnabled: Bool = true,
            bypassApolo: Bool = false,
            isLoadingOrPlaying: Bool = true,
            desiredPlaying: Bool = true,
            isInterrupted: Bool = false
        ) -> Bool {
            LiveRadioDuplicateRequestPolicy.shouldSuppress(
                requestedID: requestedID,
                requestedURL: requestedURL,
                currentID: currentID,
                currentURL: currentURL,
                apoloActive: apoloActive,
                apoloRadioEnabled: apoloRadioEnabled,
                bypassApolo: bypassApolo,
                isLoadingOrPlaying: isLoadingOrPlaying,
                desiredPlaying: desiredPlaying,
                isInterrupted: isInterrupted
            )
        }

        // Regression for log(10): two identical RTL HLS starts in 1.231s.
        expect(ignored(), "Second RTL request while loading or playing must not rebuild AVPlayerItem")
        expect(!ignored(apoloActive: false), "First station load must proceed")
        expect(!ignored(currentID: otherID), "Changing stations must proceed")
        expect(!ignored(requestedID: otherID), "Selecting a new station must proceed")
        expect(!ignored(requestedURL: alternateURL), "Refreshing an expired HLS URL must proceed")
        expect(!ignored(currentURL: nil), "Unknown current URL must proceed")
        expect(!ignored(currentURL: alternateURL), "Changed active source URL must proceed")
        expect(!ignored(isLoadingOrPlaying: false), "Paused/idle/failed session must allow explicit retry")
        expect(!ignored(desiredPlaying: false), "User-paused session must allow explicit restart")
        expect(!ignored(isInterrupted: true), "Explicit selection during interruption is not silently dropped")
        expect(!ignored(apoloRadioEnabled: false), "Turning off beta allows engine switch")
        expect(!ignored(bypassApolo: true), "Explicit MPV fallback is never blocked")
        expect(!ignored(requestedID: "youtube-song"), "Ordinary music must not be deduplicated")
        expect(!ignored(requestedID: nil), "Requests without a radio ID must proceed")
        expect(!ignored(currentID: nil), "Unknown current station must proceed")
        expect(!ignored(requestedURL: URL(string: "https://radio.example/other.m3u8")!),
               "A different stream under the same station ID must proceed")

        print("PASS: \(checks) live radio duplicate-request policy checks")
    }
}
