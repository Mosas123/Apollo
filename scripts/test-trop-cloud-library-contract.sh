#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/MusicSources/MusicCatalog.swift \
  Trop/Core/LibrarySync/TropCloudLibraryContract.swift \
  tests/LibrarySync/TropCloudLibraryContractChecks.swift \
  -o "$tmp_dir/trop-cloud-library-contract-checks"
"$tmp_dir/trop-cloud-library-contract-checks"
