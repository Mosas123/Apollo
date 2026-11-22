#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/LibrarySync/TropLibraryV2AccountIsolation.swift \
  tests/LibrarySync/TropLibraryV2AccountIsolationChecks.swift \
  -o "$temp_dir/v2-account-policy"
"$temp_dir/v2-account-policy"

# We intentionally keep local event history, total listening time and
# play counts, but never call the YouTube playback registration endpoint.
grep -Fq 'incrementPlayCount' Trop/Playback/PlaybackStateService.swift
grep -Fq 'incrementTotalPlayTime' Trop/Playback/PlaybackStateService.swift
grep -Fq 'event.inserted' Trop/Playback/PlaybackStateService.swift
if grep -Fq 'registerPlayback(' Trop/Playback/PlaybackStateService.swift; then
  echo 'Player still registers listening remotely'
  exit 1
fi
if grep -Fq 'getCachedTrackingUrl' Trop/Playback/PlaybackStateService.swift; then
  echo 'Player still reads legacy remote tracking URLs'
  exit 1
fi

# All entry points check the same V2 opt-in setting; legacy mode is intact.
for f in \
  Trop/Services/SyncBridge.swift \
  Trop/Components/AccountSheetHost.swift \
  Trop/Home/HomeViewModel.swift; do
  grep -Fq 'TropLibraryV2AccountIsolation.isEnabled' "$f"
done
grep -Fq 'if !libraryV2PreviewEnabled {' Trop/Home/HomeScreenView.swift
grep -Fq 'await viewModel.restoreSession()' Trop/Home/HomeScreenView.swift
grep -Fq 'await accountState.restoreSession()' Trop/Home/HomeScreenView.swift
grep -Fq 'await SyncBridge.checkAndSyncIfStale()' Trop/Home/HomeScreenView.swift

# Provider-side music discovery must remain accessible; this PR does not
# disable Home catalog browsing or music resolution and transport.
grep -Fq 'InnerTubeClient.tropShared.browse(browseId: "FEmusic_home")' \
  Trop/Home/HomeViewModel.swift
grep -Fq 'PlaybackManager.shared.startQueueObserver()' Trop/ContentView.swift
echo 'Trop Library V2 YouTube account isolation checks passed'
