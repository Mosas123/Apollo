#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
swiftc -swift-version 6 \
  Trop/Core/LibrarySync/LibraryImportPlanner.swift \
  Trop/Core/LibrarySync/PortableLibraryCSVImporter.swift \
  tests/LibrarySync/PortableLibraryCSVChecks.swift \
  -o "$tmp_dir/portable-import-checks"
"$tmp_dir/portable-import-checks"
