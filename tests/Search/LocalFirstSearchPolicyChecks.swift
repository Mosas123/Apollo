import Foundation

@main
struct LocalFirstSearchPolicyChecks {
    static func main() {
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
