import Foundation

/// Counted UI labels use the language's plural rules, not English suffixes.
enum AppStrings {
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: arguments)
    }

    static func songs(_ count: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString("songs.count", comment: "Number of songs"), count)
    }

    static func offlineTracks(_ count: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString("offline_tracks.count", comment: "Number of downloaded tracks"), count)
    }

    static func episodes(_ count: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString("episodes.count", comment: "Number of episodes"), count)
    }
}
