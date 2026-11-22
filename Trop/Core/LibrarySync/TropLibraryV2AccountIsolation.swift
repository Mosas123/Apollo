import Foundation

/// Library V2 is a private, local-first user collection. When enabled,
/// legacy account sync must not run just because a user visits Home.
/// YouTube remains usable as a music discovery/playback provider.
enum TropLibraryV2AccountIsolation {
    static let preferenceKey = "trop.library.v2.previewEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: preferenceKey)
    }
}
