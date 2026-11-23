#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Search/SearchLocalFirstPolicy.swift \
  tests/Search/LocalFirstSearchPolicyChecks.swift \
  -o "$temp_dir/search-local-first-checks"
"$temp_dir/search-local-first-checks"

# Verify the live view model actually wires the policy and independently
# launches the local fetch before awaiting network search.
grep -Fq "localFetchTask = Task" Trop/Search/SearchViewModel.swift
grep -Fq "SearchLocalFirstPolicy.useLocalFallback" Trop/Search/SearchViewModel.swift
grep -Fq "SearchLocalFirstPolicy.hasVisibleContent" Trop/Search/SearchViewModel.swift
grep -Fq "SearchLocalFirstPolicy.requestYouTubeCatalogue" Trop/Search/SearchViewModel.swift
grep -Fq "if requestsYouTubeCatalogue {" Trop/Search/SearchViewModel.swift
grep -Fq "await withTaskGroup(of: ProviderSearchResult.self)" Trop/Search/SearchViewModel.swift
grep -Fq "suggestions = []" Trop/Search/SearchViewModel.swift
# A V2 search must read Trop-owned UUID rows instead of the legacy tables,
# and the UI must not feed saved UUIDs into YouTube YTItem playback.
grep -Fq "async let saved = TropLibraryV2Store.recordings()" Trop/Search/SearchViewModel.swift
grep -Fq "async let lists = TropLibraryV2Store.playlists()" Trop/Search/SearchViewModel.swift
grep -Fq "async let radio = TropLibraryV2RadioStore.favorites()" Trop/Search/SearchViewModel.swift
grep -Fq "guard !TropLibraryV2AccountIsolation.isEnabled else { return [] }" Trop/Search/SearchViewModel.swift
grep -Fq "if viewModel.displaysV2LibraryResults {" Trop/Search/SearchView.swift
grep -Fq "TropLibraryV2PlaylistScreen(playlist: playlist)" Trop/Search/SearchView.swift
grep -Fq "RadioPlaybackCoordinator.playSaved(" Trop/Search/SearchView.swift

# Saved songs in Search must route through explicit source aliases, never
# through the legacy YouTube YTItem router.
grep -Fq 'TropLibraryV2PlaybackRouter.playSaved(recording)' Trop/Search/SearchView.swift
grep -Fq 'TropLibraryV2PlaybackSourceError' Trop/Search/SearchView.swift
# Production Home and Explore must not bootstrap InnerTube feeds when V2
# owns the library. These source checks catch accidental gate removal.
grep -Fq "if libraryV2PreviewEnabled {" Trop/Home/HomeScreenView.swift
grep -Fq "v2HomeContent" Trop/Home/HomeScreenView.swift
grep -Fq "guard !TropLibraryV2AccountIsolation.isEnabled else { return }" Trop/Home/HomeViewModel.swift
grep -Fq "if libraryV2PreviewEnabled {" Trop/Explore/ExploreView.swift
grep -Fq "guard !TropLibraryV2AccountIsolation.isEnabled else { return }" Trop/Explore/ExploreViewModel.swift

# Global music discovery is separate from Library V2 and requires no
# saved artists or recordings. Its data comes from public ListenBrainz stats.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/MusicSources/TropGlobalMusicCatalog.swift \
  tests/MusicSources/TropGlobalMusicCatalogChecks.swift \
  -o "$temp_dir/trop-global-catalog"
"$temp_dir/trop-global-catalog"
swiftc -frontend -parse Trop/Explore/ExploreView.swift
swiftc -frontend -parse Trop/Home/HomeScreenView.swift
swiftc -frontend -parse Trop/Explore/TropGlobalRecordingSheet.swift
swiftc -frontend -parse Trop/ContentView.swift

# Buttons from Home must change the actual TabView selection, including
# when the Explore tab is hidden for legacy users.
grep -Fq 'router.selectedTabIndex = 4' Trop/Home/HomeScreenView.swift
grep -Fq 'AppRouter.shared.$selectedTabIndex.dropFirst()' Trop/ContentView.swift
grep -Fq 'if settings.showExploreTab || libraryV2PreviewEnabled {' Trop/ContentView.swift
grep -Fq 'TropGlobalMusicCatalog.shared' Trop/Home/HomeScreenView.swift
grep -Fq 'TropGlobalMusicCatalog.shared' Trop/Explore/ExploreView.swift
grep -Fq 'TropGlobalRecordingSheet(recording: recording)' Trop/Home/HomeScreenView.swift
grep -Fq 'TropGlobalRecordingSheet(recording: recording)' Trop/Explore/ExploreView.swift
grep -Fq 'TropLibraryV2AudioDiscovery.inspect(' Trop/Explore/TropGlobalRecordingSheet.swift
grep -Fq 'TropLibraryV2Store.createItem(' Trop/Explore/TropGlobalRecordingSheet.swift
grep -Fq 'thumbnailUrl: artworkURL' Trop/Core/LibrarySync/TropLibraryV2PlaybackRouter.swift

python3 - <<'EXPLORE_SOURCE_CHECK'
from pathlib import Path
view = Path("Trop/Explore/ExploreView.swift").read_text()
home = Path("Trop/Home/HomeScreenView.swift").read_text()
catalog = Path("Trop/Core/MusicSources/TropGlobalMusicCatalog.swift").read_text()
v2_view = view.split("private var v2AudioExplore:", 1)[1].split(
    "private var content:", 1
)[0]
v2_home = home.split("private var v2HomeContent:", 1)[1].split(
    "private var homescreenContent:", 1
)[0]
assert all(word not in v2_view for word in [
    "InnerTubeClient", "YouTubeListItemView", "SyncBridge",
    "TropLibraryV2Store.recordings()", "selectedV2Artist"
])
assert all(word not in v2_home for word in [
    "InnerTubeClient", "YouTubeListItemView", "SyncBridge.mutations"
])
assert "api.listenbrainz.org/1/stats/sitewide/recordings" in catalog
assert "URLSession.shared.data(for:" in catalog
assert "TropGlobalRecording" in v2_home
assert "TropGlobalRecording" in v2_view
assert "popularRecordings(forceRefresh: force)" in v2_view
print("Home + Explore V2: global metadata, real navigation and no YouTube feed passed")
EXPLORE_SOURCE_CHECK
# Public V2 Search must query MusicBrainz identities regardless of local
# saved rows and expose Library only when explicitly selected.
grep -Fq 'searchRecordingsByArtist(' Trop/Search/SearchViewModel.swift
grep -Fq 'MusicBrainzIdentityCatalog().searchAlbums(' Trop/Search/SearchViewModel.swift
grep -Fq 'MusicBrainzIdentityCatalog().searchArtists(' Trop/Search/SearchViewModel.swift
grep -Fq 'catalogRecordings' Trop/Search/SearchViewModel.swift
grep -Fq 'catalogAlbums' Trop/Search/SearchViewModel.swift
grep -Fq 'catalogArtists' Trop/Search/SearchViewModel.swift
grep -Fq 'TropGlobalRecordingSheet(recording: recording)' Trop/Search/SearchView.swift
grep -Fq 'v2SectionHeader("Songs · MusicBrainz")' Trop/Search/SearchView.swift
grep -Fq 'v2SectionHeader("Albums · MusicBrainz")' Trop/Search/SearchView.swift
grep -Fq 'v2SectionHeader("Artists · MusicBrainz")' Trop/Search/SearchView.swift
swiftc -frontend -parse Trop/Search/SearchViewModel.swift
swiftc -frontend -parse Trop/Search/SearchView.swift
python3 - <<'GLOBAL_SEARCH_ASSERTIONS'
from pathlib import Path
model = Path("Trop/Search/SearchViewModel.swift").read_text()
view = Path("Trop/Search/SearchView.swift").read_text()
library_gate = model.split("var displaysV2LibraryResults:", 1)[1].split(
    "var showsCatalogRecordings:", 1
)[0]
assert "&& isShowingLibrary" in library_gate
assert "selectedSectionFilter == nil" not in library_gate
metadata_search = model.split(
    "// Search public MusicBrainz identities", 1
)[1].split("// Music Add-ons (Stremio, read-only)", 1)[0]
assert "MusicBrainzIdentityCatalog" in metadata_search
assert "SearchService.shared.search" not in metadata_search
assert "InnerTube" not in metadata_search
assert "if includeProviders" in metadata_search
assert "group.cancelAll()" in metadata_search
assert "isShowingLibrary && (" in model
assert "if viewModel.showsCatalogRecordings" in view
assert "if viewModel.displaysV2LibraryResults" in view
print("Global V2 Search and optional Library scope wiring passed")
GLOBAL_SEARCH_ASSERTIONS
