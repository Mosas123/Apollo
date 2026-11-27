#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/playback-event-policy-checks"

swiftc \
  "$ROOT/Apollo/Playback/PlaybackEventPolicy.swift" \
  "$ROOT/tests/Radio/PlaybackEventPolicyChecks.swift" \
  -o "$OUT"
"$OUT"
