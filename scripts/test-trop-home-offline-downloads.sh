#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Home/TropOfflineHomePolicy.swift \
  tests/Home/TropOfflineHomePolicyChecks.swift \
  -o "$temp_dir/trop-offline-home"
"$temp_dir/trop-offline-home"

# V2 Home displays local metadata without relying on a network failure.
# Saved metadata is NOT automatically playable offline; only verified local
# downloads use the existing DownloadsView playback path.
grep -Fq 'v2HomeContent' Trop/Home/HomeScreenView.swift
grep -Fq 'TropLibraryV2Store.recordings()' Trop/Home/HomeScreenView.swift
grep -Fq 'TropLibraryV2Store.playlists()' Trop/Home/HomeScreenView.swift
grep -Fq 'TropLibraryV2RadioStore.favorites()' Trop/Home/HomeScreenView.swift
grep -Fq 'RadioPlaybackCoordinator.playSaved(' Trop/Home/HomeScreenView.swift
grep -Fq 'DownloadsView()' Trop/Home/HomeScreenView.swift
grep -Fq 'await downloadManager.reload()' Trop/Home/HomeScreenView.swift
grep -Fq 'errorView(error)' Trop/Home/HomeScreenView.swift

# DownloadsView retains its local URL validation, source MIME, and playback
# generation guard. Do not replace it with streaming PlaybackQueue calls.
grep -Fq 'await downloadManager.localURL(for: song.videoId)' Trop/Library/DownloadsView.swift
grep -Fq 'intentGeneration: intent' Trop/Library/DownloadsView.swift
grep -Fq 'LocalAudioFilePolicy.mimeHint(for: localURL)' Trop/Library/DownloadsView.swift
grep -Fq 'navigationTitle(embeddedInHome ? "Home" : "Downloads")' Trop/Library/DownloadsView.swift

# The V2 metadata surface cannot start a saved recording through the legacy
# YouTube-keyed queue. Audio playback requires a separately resolved source.
v2_surface="$(sed -n '/private var v2HomeContent:/,/private var homescreenContent:/p' \
  Trop/Home/HomeScreenView.swift)"
if printf '%s' "$v2_surface" | grep -Eq 'PlaybackQueue\.play|InnerTubeClient|SyncBridge\.mutations'; then
  echo 'V2 Home must not play unresolved metadata or call YouTube'
  exit 1
fi
echo 'Trop offline Home local metadata + verified downloads checks passed'
