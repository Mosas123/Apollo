#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  Trop/Core/MusicSources/MusicCatalog.swift \
  Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
  Trop/Core/LibrarySync/TropLibraryV2PlaybackCandidate.swift \
  tests/LibrarySync/TropLibraryV2PlaylistPickerChecks.swift \
  -o "$tmp_dir/v2-playlist-picker"
"$tmp_dir/v2-playlist-picker"

# Both entry menus must expose V2 playlist access for external songs.
grep -Fq 'else if TropLibraryV2AccountIsolation.isEnabled' Trop/Audio/PlayerMenuSheet.swift
grep -Fq 'if TropLibraryV2AccountIsolation.isEnabled' Trop/Components/SongMenuSheet.swift
grep -Fq 'AddSongToPlaylistSheet(song: song)' Trop/Audio/PlayerMenuSheet.swift
grep -Fq 'AddSongToPlaylistSheet(song: song)' Trop/Components/SongMenuSheet.swift

# The shared sheet must list local playlists and call the new transaction, while
# retaining legacy SyncBridge calls behind the V2 mode switch.
grep -Fq 'useLibraryV2 = TropLibraryV2AccountIsolation.isEnabled' Trop/Audio/PlayerMenuSheet.swift
grep -Fq 'TropLibraryV2Store.playlists()' Trop/Audio/PlayerMenuSheet.swift
grep -Fq 'TropLibraryV2Store.saveToPlaylist(' Trop/Audio/PlayerMenuSheet.swift
grep -Fq 'SyncBridge.mutations.addToPlaylist' Trop/Audio/PlayerMenuSheet.swift
grep -Fq 'pendingIDs.insert(playlist.id)' Trop/Audio/PlayerMenuSheet.swift

# Creating/adding a V2 song must be a single GRDB write transaction with
# source alias, Trop recording, playlist and membership all local.
grep -Fq 'static func saveToPlaylist(' Trop/Core/LibrarySync/TropLibraryV2Store.swift
grep -Fq 'return try await DatabaseService.shared.writeReturning { db in' Trop/Core/LibrarySync/TropLibraryV2Store.swift
grep -Fq 'INSERT INTO trop_v2_source_alias' Trop/Core/LibrarySync/TropLibraryV2Store.swift
grep -Fq 'INSERT INTO trop_v2_playlist_entry' Trop/Core/LibrarySync/TropLibraryV2Store.swift

echo 'Trop V2 player/addon playlist picker source wiring checks passed'
