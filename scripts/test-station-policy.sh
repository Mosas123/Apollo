#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/station-policy-checks"

swiftc \
  "$ROOT/Apollo/Radio/StationDiversityPolicy.swift" \
  "$ROOT/Apollo/Catalog/MusicBrainz/MusicBrainzTagPolicy.swift" \
  "$ROOT/tests/Radio/StationPolicyChecks.swift" \
  -o "$OUT"
"$OUT"
