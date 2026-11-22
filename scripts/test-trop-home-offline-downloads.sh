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

# The only offline music surface uses the established local playback path.
grep -Fq 'DownloadsView(embeddedInHome: true)' Trop/Home/HomeScreenView.swift
grep -Fq 'downloadManager.tracks.count' Trop/Home/HomeScreenView.swift
grep -Fq 'TropOfflineHomePolicy.isDisconnected(error)' Trop/Home/HomeScreenView.swift
grep -Fq 'errorView(error)' Trop/Home/HomeScreenView.swift
grep -Fq 'await downloadManager.reload()' Trop/Home/HomeScreenView.swift

# DownloadsView retains its local URL validation, source MIME, and playback
# generation guard. Do not replace it with streaming PlaybackQueue calls.
grep -Fq 'await downloadManager.localURL(for: song.videoId)' Trop/Library/DownloadsView.swift
grep -Fq 'intentGeneration: intent' Trop/Library/DownloadsView.swift
grep -Fq 'LocalAudioFilePolicy.mimeHint(for: localURL)' Trop/Library/DownloadsView.swift
grep -Fq 'navigationTitle(embeddedInHome ? "Home" : "Downloads")' Trop/Library/DownloadsView.swift

# Do not add provider metadata-only radio or V2 liked IDs to Home offline.
if grep -E 'TropLibraryV2Store.recordings\(|TropLibraryV2RadioStore.favorites\(' \
  Trop/Home/HomeScreenView.swift; then
  echo 'Offline Home must only display local downloaded audio'
  exit 1
fi
echo 'Trop offline Home downloads-only wiring checks passed'
