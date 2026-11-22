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
# Production Home and Explore must not bootstrap InnerTube feeds when V2
# owns the library. These source checks catch accidental gate removal.
grep -Fq "if libraryV2PreviewEnabled {" Trop/Home/HomeScreenView.swift
grep -Fq "v2HomeContent" Trop/Home/HomeScreenView.swift
grep -Fq "guard !TropLibraryV2AccountIsolation.isEnabled else { return }" Trop/Home/HomeViewModel.swift
grep -Fq "if libraryV2PreviewEnabled {" Trop/Explore/ExploreView.swift
grep -Fq "guard !TropLibraryV2AccountIsolation.isEnabled else { return }" Trop/Explore/ExploreViewModel.swift
