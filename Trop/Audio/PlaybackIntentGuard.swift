import Foundation

/// Pure ownership fence for asynchronous playback work. Track identity
/// alone is insufficient: A -> B -> A is an ABA transition, so the monotonic
/// intent generation must match as well.
enum PlaybackIntentGuard {
    static func owns(
        expectedGeneration: Int,
        expectedVideoId: String,
        generation: Int,
        videoId: String?
    ) -> Bool {
        expectedGeneration == generation && expectedVideoId == videoId
    }

    static func isLatest(
        serial: UInt64,
        latestSerial: UInt64
    ) -> Bool {
        serial == latestSerial
    }
}
