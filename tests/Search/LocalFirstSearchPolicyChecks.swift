import Foundation

@main
struct LocalFirstSearchPolicyChecks {
    static func main() {
        // V2 does not use YouTube Music for catalogues or typeahead. The
        // independent YouTube audio resolver remains a separate concern.
        precondition(!SearchLocalFirstPolicy.requestYouTubeCatalogue(
            libraryV2Enabled: true
        ))
        precondition(SearchLocalFirstPolicy.requestYouTubeCatalogue(
            libraryV2Enabled: false
        ))

        // Saved V2 search uses local, provider-free title/artist matching.
        // It never parses UUIDs as YouTube video IDs or SQL wildcards.
        precondition(SearchLocalFirstPolicy.matchesV2LibraryItem(
            query: "cafe", title: "Café del Mar"
        ))
        precondition(SearchLocalFirstPolicy.matchesV2LibraryItem(
            query: "NUEVAYOL", title: "Otra canción", subtitle: "Nuevayol"
        ))
        precondition(SearchLocalFirstPolicy.matchesV2LibraryItem(
            query: "%", title: "100% música"
        ))
        precondition(!SearchLocalFirstPolicy.matchesV2LibraryItem(
            query: "_", title: "Sin guiones"
        ))
        precondition(!SearchLocalFirstPolicy.matchesV2LibraryItem(
            query: "   ", title: "Saved"
        ))
        precondition(!SearchLocalFirstPolicy.matchesV2LibraryItem(
            query: "video", title: "Pure audio", subtitle: nil
        ))

        // A slow/stuck YouTube request must not hide existing saved items.
        precondition(SearchLocalFirstPolicy.useLocalFallback(
            showingLibrary: false, selectedFilter: nil,
            hasRemoteSections: false, hasRemoteHero: false,
            hasLocalSections: true
        ))
        precondition(SearchLocalFirstPolicy.hasVisibleContent(
            hasRemoteSections: false, hasRemoteHero: false,
            hasLocalSections: true, hasExternalProviderTracks: false
        ))

        // Keep the explicitly selected Library filter intact.
        precondition(SearchLocalFirstPolicy.useLocalFallback(
            showingLibrary: true, selectedFilter: "Songs",
            hasRemoteSections: true, hasRemoteHero: true,
            hasLocalSections: true
        ))

        // As remote results arrive, preserve the old All Results layout.
        precondition(!SearchLocalFirstPolicy.useLocalFallback(
            showingLibrary: false, selectedFilter: nil,
            hasRemoteSections: true, hasRemoteHero: false,
            hasLocalSections: true
        ))
        precondition(!SearchLocalFirstPolicy.useLocalFallback(
            showingLibrary: false, selectedFilter: nil,
            hasRemoteSections: false, hasRemoteHero: true,
            hasLocalSections: true
        ))

        // Remote-section filter should never unexpectedly show local rows.
        precondition(!SearchLocalFirstPolicy.useLocalFallback(
            showingLibrary: false, selectedFilter: "Albums",
            hasRemoteSections: false, hasRemoteHero: false,
            hasLocalSections: true
        ))
        precondition(!SearchLocalFirstPolicy.useLocalFallback(
            showingLibrary: false, selectedFilter: nil,
            hasRemoteSections: false, hasRemoteHero: false,
            hasLocalSections: false
        ))
        precondition(!SearchLocalFirstPolicy.hasVisibleContent(
            hasRemoteSections: false, hasRemoteHero: false,
            hasLocalSections: false, hasExternalProviderTracks: false
        ))

        // Independent providers may still yield valid results on a YT miss.
        precondition(SearchLocalFirstPolicy.hasVisibleContent(
            hasRemoteSections: false, hasRemoteHero: false,
            hasLocalSections: false, hasExternalProviderTracks: true
        ))
        print("Local-first search presentation policy checks passed")
    }
}
