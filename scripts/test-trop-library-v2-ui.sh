#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# V2 requires explicit user opt-in; existing data keeps using the old UI
# until the new save routes are completely validated on an iPhone.
grep -Fq 'libraryV2PreviewEnabled = false' Trop/ContentView.swift
grep -Fq 'TropLibraryV2Screen()' Trop/ContentView.swift
grep -Fq 'Toggle("Use Trop Library V2"' Trop/Settings/SettingsView.swift
grep -Fq 'guard !libraryV2PreviewEnabled else { return }' Trop/Settings/SettingsView.swift

# There must be only user-initiated writes, no hidden YouTube sync or
# source API calls inside the new screen.
grep -Fq 'TropLibraryV2Store.savePlaybackRecording(' \
  Trop/Core/LibrarySync/TropLibraryV2PlaybackCandidate.swift
grep -Fq 'TropLibraryV2Store.createPlaylist(named:' \
  Trop/Library/TropLibraryV2Screen.swift
grep -Fq 'TropLibraryV2Store.appendRecording(' \
  Trop/Library/TropLibraryV2Screen.swift
# Home V2 navigates to this playlist from another Swift source file.
# A file-private view compiles only until Home references it.
grep -Fq 'TropLibraryV2PlaylistScreen(playlist: playlist)' \
  Trop/Home/HomeScreenView.swift
grep -Eq '^struct TropLibraryV2PlaylistScreen: View \{' \
  Trop/Library/TropLibraryV2Screen.swift
if grep -Eq '^private struct TropLibraryV2PlaylistScreen' \
  Trop/Library/TropLibraryV2Screen.swift; then
  echo 'V2 playlist view cannot be private while Home links to it'
  exit 1
fi
grep -Fq 'TropLibraryV2Store.setLiked(' \
  Trop/Library/TropLibraryV2Screen.swift
grep -Fq 'TropLibraryV2Store.savePlaybackRecording(' \
  Trop/Services/LikeStore.swift
grep -Fq 'TropLibraryV2Store.setLikedForSource(' \
  Trop/Services/LikeStore.swift
grep -Fq 'TropLibraryV2Store.likedPlaybackIDs()' \
  Trop/Services/LikeStore.swift
grep -Fq 'onChange(of: libraryV2PreviewEnabled)' \
  Trop/ContentView.swift
if grep -vE '^[[:space:]]*//' Trop/Library/TropLibraryV2Screen.swift \
  | grep -E 'SyncBridge|CookieStore|InnerTube|remoteMutation'; then
  echo 'V2 Library UI unexpectedly uses legacy account mutations'
  exit 1
fi

# Keep pure schema invariants from the foundation in every UI PR.
bash scripts/test-trop-library-v2-foundation.sh
echo 'Trop Library V2 UI wiring checks passed'
