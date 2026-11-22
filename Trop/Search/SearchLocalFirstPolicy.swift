import Foundation

/// Search-phase decisions that do not require a network connection.
/// The UI may show saved local items while InnerTube is still resolving;
/// YouTube results must never be required to make a local row visible.
enum SearchLocalFirstPolicy {
    /// V2 owns its catalogue. InnerTube search and typeahead belong to the
    /// old YouTube Music catalogue, never the independent Library V2.
    /// YouTube may still resolve a provider-scoped audio track separately.
    static func requestYouTubeCatalogue(libraryV2Enabled: Bool) -> Bool {
        !libraryV2Enabled
    }

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

    /// Match saved Trop-owned metadata without consulting legacy YouTube rows.
    /// Standard containment handles case and accents in user-entered names.
    static func matchesV2LibraryItem(
        query: String,
        title: String,
        subtitle: String? = nil
    ) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        return title.localizedStandardContains(needle)
            || (subtitle?.localizedStandardContains(needle) ?? false)
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
