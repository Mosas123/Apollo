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

# Home V2 is a public discovery surface. Library is a different tab.
# No private saved songs, playlists or radio favorites should fill Home.
grep -Fq 'v2HomeContent' Trop/Home/HomeScreenView.swift
grep -Fq 'v2DiscoveryCard' Trop/Home/HomeScreenView.swift
grep -Fq 'HorizontalSection(title: "Popular on ListenBrainz"' Trop/Home/HomeScreenView.swift
grep -Fq 'TropLibraryV2ArtworkView(' Trop/Home/HomeScreenView.swift
grep -Fq 'TropGlobalPlaybackCoordinator.play(recording)' Trop/Home/HomeScreenView.swift
grep -Fq 'TropGlobalPlaybackCoordinator.save(recording)' Trop/Home/HomeScreenView.swift
grep -Fq 'Audio unavailable' Trop/Home/HomeScreenView.swift
grep -Fq 'await downloadManager.reload()' Trop/Home/HomeScreenView.swift
grep -Fq 'errorView(error)' Trop/Home/HomeScreenView.swift
swiftc -frontend -parse Trop/Home/HomeScreenView.swift

python3 - <<'HOME_IS_NOT_LIBRARY'
from pathlib import Path
s = Path("Trop/Home/HomeScreenView.swift").read_text()
start = s.index("private var v2HomeContent:")
end = s.index("private var homescreenContent:", start)
v2 = s[start:end]
for forbidden in (
    "TropLibraryV2Store.recordings(", "TropLibraryV2Store.playlists(",
    "TropLibraryV2RadioStore.favorites(", "Your playlists",
    "Recently saved", "Your radio stations",
    "TropGlobalRecordingSheet(", "TropLibraryV2PlaybackRouter.playSaved("
):
    assert forbidden not in v2, f"Saved-library content leaked into Home: {forbidden}"
assert "TropGlobalMusicCatalog.shared" in v2
assert "TropGlobalPlaybackCoordinator.play(recording)" in v2
assert "TropGlobalPlaybackCoordinator.save(recording)" in v2
print("Home V2 source independently discovers music without Library")
HOME_IS_NOT_LIBRARY

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
if printf '%s' "$v2_surface" | grep -Eq 'PlaybackQueue\.play|InnerTubeClient|SyncBridge\.mutations|SurpriseMeService|YTItem'; then
  echo 'V2 Home must not play unresolved metadata or call YouTube'
  exit 1
fi
echo 'Trop independent Home + verified Downloads checks passed'
