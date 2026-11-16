#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
swiftc -swift-version 6 \
  Trop/Core/MusicSources/MusicCatalog.swift \
  Trop/Core/MusicSources/AudiusClient.swift \
  tests/MusicSources/AudiusClientChecks.swift \
  -o "$tmp_dir/audius-client-checks"
"$tmp_dir/audius-client-checks"
