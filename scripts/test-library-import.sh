#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
swiftc -swift-version 6 \
  Apollo/Core/LibrarySync/LibraryImportPlanner.swift \
  tests/LibrarySync/LibraryImportPlannerChecks.swift \
  -o "$tmp_dir/library-import-checks"
"$tmp_dir/library-import-checks"
