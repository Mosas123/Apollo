#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
swiftc -swift-version 6 \
  Apollo/Core/MusicAddons/MusicAddonManifest.swift \
  Apollo/Core/MusicAddons/MusicAddonRegistry.swift \
  tests/MusicAddons/MusicAddonManagerChecks.swift \
  -o "$tmp_dir/music-addon-manager-checks"
"$tmp_dir/music-addon-manager-checks"
