import Foundation

/// Prevents repeated station selection from tearing down a healthy native
/// live session and recreating its AVPlayerItem. This is a request guard,
/// not a workaround for AVFoundation's timed-metadata crash.
enum LiveRadioDuplicateRequestPolicy {
    struct ActiveSession {
        let stationID: String?
        let streamURL: URL?
        let apoloActive: Bool
        let apoloRadioEnabled: Bool
        let isLoadingOrPlaying: Bool
        let desiredPlaying: Bool
        let isInterrupted: Bool
    }

    static func shouldSuppress(
        requestedID: String?,
        requestedURL: URL,
        bypassApolo: Bool,
        active: ActiveSession
    ) -> Bool {
        guard !bypassApolo,
              active.apoloRadioEnabled,
              active.apoloActive,
              active.isLoadingOrPlaying,
              active.desiredPlaying,
              !active.isInterrupted,
              let requestedID,
              requestedID.hasPrefix("radio:"),
              requestedID == active.stationID,
              let currentURL = active.streamURL else {
            return false
        }
        // Compare the exact stream, including query parameters. Same station
        // ID with a new URL/codec is a real replacement, not a duplicate.
        return requestedURL == currentURL
    }
}
