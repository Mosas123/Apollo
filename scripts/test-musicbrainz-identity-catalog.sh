#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/MusicSources/MusicCatalog.swift \
  Trop/Core/MusicSources/MusicBrainzIdentityCatalog.swift \
  tests/MusicSources/MusicBrainzIdentityCatalogChecks.swift \
  -o "$tmp_dir/musicbrainz-identity-checks"
"$tmp_dir/musicbrainz-identity-checks"
