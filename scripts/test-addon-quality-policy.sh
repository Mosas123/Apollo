#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  Apollo/Settings/MusicQualityMode.swift \
  Apollo/Core/MusicAddons/AddonStreamQualityPolicy.swift \
  tests/MusicAddons/AddonQualityPolicyChecks.swift \
  -o "$tmp_dir/addon-quality-checks"
"$tmp_dir/addon-quality-checks"

# Capture each entry path: directly selected streams, source matching,
# previously cached matches and Stremio's multi-URL selection.
grep -Fq 'policy.accepts(stream)' Apollo/Audio/PlaybackManager.swift
grep -Fq 'policy.accepts(stream)' Apollo/Core/MusicAddons/AddonSourceResolver.swift
grep -Fq 'policy.accepts(cached.stream)' Apollo/Core/MusicAddons/AddonSourceResolver.swift
grep -Fq 'policy.rank(candidate)' Apollo/Core/MusicAddons/MusicAddonClient.swift
grep -Fq 'allowHiRes: policy.allowHiRes' Apollo/Audio/PlaybackManager.swift

# Older Lossless selection must not silently opt people into 24-bit music.
grep -Fq 'preferHiRes = Self.load(Keys.preferHiRes, default: false)' Apollo/Settings/SettingsStore.swift
if grep -Fq 'default: (d.object(forKey: Keys.legacyPreferLossless)' Apollo/Settings/SettingsStore.swift; then
  echo "Legacy Lossless setting must not enable Hi-Res"
  exit 1
fi

echo "Addon quality limits checked in direct, automatic, cached and settings paths"
