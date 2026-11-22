#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/SponsorBlock/SponsorBlockSkipPolicy.swift \
  tests/SponsorBlock/SponsorBlockSourceScopeChecks.swift \
  -o "$temp_dir/sponsorblock-source-checks"
"$temp_dir/sponsorblock-source-checks"

# Never regress the actual call sites: matching a videoId and stream URL
# does NOT certify the source as YouTube. Both gate and intro bypass matter.
python3 - <<'PY'
from pathlib import Path
integration=Path("Trop/SponsorBlock/SponsorBlockIntegration.swift").read_text()
manager=Path("Trop/Audio/PlaybackManager.swift").read_text()
policy=Path("Trop/SponsorBlock/SponsorBlockSkipPolicy.swift").read_text()
assert "SponsorBlockSkipPolicy.allowsSource(clientName: source.clientName)" in integration
assert "bypassSponsorBlock: externalSource" in manager
assert "SponsorBlockSkipPolicy.allowsSource(clientName: audioResult.clientName)" in manager
assert "source.streamUrl == nowPlaying.currentStreamURL" in integration
assert "source.videoId == id" in integration
assert '"addon"' not in policy.split("static func allowsSource")[1].split("default:")[0]
print("SponsorBlock call-site provenance protections passed")
PY
