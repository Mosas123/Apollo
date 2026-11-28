#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/playlist-csv-checks"

swiftc \
  "$ROOT/Apollo/Core/LibrarySync/PlaylistCSVImporter.swift" \
  "$ROOT/tests/LibrarySync/PlaylistCSVImporterChecks.swift" \
  -o "$OUT"
"$OUT"
