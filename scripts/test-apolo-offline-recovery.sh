#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Audio/PlayerController/ApoloOfflineRecoveryPolicy.swift \
  tests/Audio/ApoloOfflineRecoveryPolicyChecks.swift \
  -o "$temp_dir/apolo-offline-recovery-checks"
"$temp_dir/apolo-offline-recovery-checks"

# Source wiring gates: a lost Internet route must not enter the old
# unconditional Apolo -> MPVKit path before this policy can intervene.
grep -Fq 'import Network' Trop/Audio/PlayerController/PlayerController.swift
grep -Fq 'apoloNetworkMonitor.pathUpdateHandler' Trop/Audio/PlayerController/PlayerController.swift
grep -Fq 'ApoloOfflineRecoveryPolicy.shouldHold' Trop/Audio/PlayerController/PlayerController.swift
grep -Fq 'retryOfflineApoloIfNeeded(reason: "networkRestored")' Trop/Audio/PlayerController/PlayerController.swift
grep -Fq 'NowPlaying.shared.rememberInterruptedPlayback(' Trop/Audio/PlayerController/PlayerController.swift
