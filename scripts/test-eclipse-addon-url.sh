#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  Apollo/Core/MusicAddons/EclipseAddonURL.swift \
  tests/MusicAddons/EclipseAddonURLChecks.swift \
  -o "$temp_dir/eclipse-addon-url"
"$temp_dir/eclipse-addon-url"

# Ensure search-to-stream IDs and album IDs share the safe URL builder.
grep -Fq 'resource: "stream"' Apollo/Core/MusicAddons/MusicAddonClient.swift
grep -Fq 'resource: "album"' Apollo/Core/MusicAddons/MusicAddonClient.swift
if grep -Fq 'appendingPathComponent(encoded)' Apollo/Core/MusicAddons/MusicAddonClient.swift; then
  echo 'Do not pass pre-encoded IDs into URL.appendingPathComponent'
  exit 1
fi

echo 'Eclipse URL request construction checks passed'
