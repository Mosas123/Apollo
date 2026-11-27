#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
swiftc -swift-version 6 \
  Apollo/Core/MusicSources/MusicCatalog.swift \
  Apollo/Core/MusicSources/QobuzClient.swift \
  tests/MusicSources/QobuzClientChecks.swift \
  -o "$tmp_dir/qobuz-client-checks"
"$tmp_dir/qobuz-client-checks"
