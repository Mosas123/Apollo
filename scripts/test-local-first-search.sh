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

# Explore V2 selects a small number of saved artists locally and searches
# independent providers only after the user chooses one. No YouTube feed,
# automatic mass matching, or unverified claim of official chart rankings.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Explore/ExploreV2DiscoveryPolicy.swift \
  tests/Explore/ExploreV2DiscoveryPolicyChecks.swift \
  -o "$temp_dir/explore-v2-discovery-checks"
"$temp_dir/explore-v2-discovery-checks"
swiftc -frontend -parse Trop/Explore/ExploreView.swift
swiftc -frontend -parse Trop/Explore/ExploreViewModel.swift
grep -Fq 'TropLibraryV2Store.savedCatalogItems(kind: .artist)' \
  Trop/Explore/ExploreView.swift
grep -Fq 'ExploreV2ProviderDiscovery.tracks(for: artist)' \
  Trop/Explore/ExploreView.swift
grep -Fq 'PlaybackQueue.play(' Trop/Explore/ExploreView.swift
grep -Fq 'MusicAddonsStore.shared.enabledStremioInstallations.prefix(' \
  Trop/Explore/ExploreViewModel.swift
python3 - <<'EXPLORE_SOURCE_CHECK'
from pathlib import Path
view = Path("Trop/Explore/ExploreView.swift").read_text()
model = Path("Trop/Explore/ExploreViewModel.swift").read_text()
v2_view = view.split("private var v2AudioExplore:", 1)[1].split(
    "private var content:", 1
)[0]
v2_model = model.split("enum ExploreV2ProviderDiscovery", 1)[1]
assert all(word not in v2_view for word in [
    "InnerTubeClient", "YouTubeListItemView", "SyncBridge", "FEmusic_explore"
])
assert all(word not in v2_model for word in [
    "InnerTubeClient", "SyncBridge", "youtube", "FEmusic_explore"
])
assert "withTaskGroup" in v2_model
assert "isStreamable" in v2_model
assert "seen.insert($0.id)" in v2_model
assert "guard !Task.isCancelled" in v2_model
assert "selectedV2Artist == artist" in v2_view
print("Explore V2 independent, user-initiated, cancellable search wiring passed")
EXPLORE_SOURCE_CHECK
