import Foundation

/// Search-phase decisions that do not require a network connection.
/// The UI may show saved local items while InnerTube is still resolving;
/// YouTube results must never be required to make a local row visible.
enum SearchLocalFirstPolicy {
    static func useLocalFallback(
        showingLibrary: Bool,
        selectedFilter: String?,
        hasRemoteSections: Bool,
        hasRemoteHero: Bool,
        hasLocalSections: Bool
    ) -> Bool {
        if showingLibrary { return true }
        return selectedFilter == nil
            && !hasRemoteSections
            && !hasRemoteHero
            && hasLocalSections
    }

    static func hasVisibleContent(
        hasRemoteSections: Bool,
        hasRemoteHero: Bool,
        hasLocalSections: Bool,
        hasExternalProviderTracks: Bool
    ) -> Bool {
        hasRemoteSections || hasRemoteHero || hasLocalSections || hasExternalProviderTracks
    }
}
