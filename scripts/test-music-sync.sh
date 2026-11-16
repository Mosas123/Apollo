#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
swiftc -swift-version 6 \
  Trop/Core/LibrarySync/MusicSyncPlanner.swift \
  tests/LibrarySync/MusicSyncPlannerChecks.swift \
  -o "$tmp_dir/music-sync-checks"
"$tmp_dir/music-sync-checks"
