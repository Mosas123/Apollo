#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
swiftc -swift-version 6 \
  Trop/Core/MusicAddons/MusicAddonManifest.swift \
  Trop/Core/MusicAddons/MusicAddonRegistry.swift \
  tests/MusicAddons/MusicAddonChecks.swift \
  -o "$tmp_dir/music-addon-checks"
"$tmp_dir/music-addon-checks"
