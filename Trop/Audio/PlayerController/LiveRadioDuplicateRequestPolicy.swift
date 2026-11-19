import Foundation

/// Prevents a repeated station selection from tearing down a healthy native
/// live session and recreating its AVPlayerItem. This is a *request* guard,
/// not a workaround for AVFoundation's timed-metadata crash.
enum LiveRadioDuplicateRequestPolicy {
    static func shouldSuppress(
        requestedID: String?,
        requestedURL: URL,
        currentID: String?,
        currentURL: URL?,
        apoloActive: Bool,
        apoloRadioEnabled: Bool,
        bypassApolo: Bool,
        isLoadingOrPlaying: Bool,
        desiredPlaying: Bool,
        isInterrupted: Bool
    ) -> Bool {
        guard !bypassApolo,
              apoloRadioEnabled,
              apoloActive,
              isLoadingOrPlaying,
              desiredPlaying,
              !isInterrupted,
              let requestedID,
              requestedID.hasPrefix("radio:"),
              requestedID == currentID,
              let currentURL else {
            return false
        }
        // Compare the exact stream, including query parameters. Same station
        // ID with a new URL/codec is a real replacement, not a duplicate.
        return requestedURL == currentURL
    }
}
