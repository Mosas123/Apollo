#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/LibrarySync/TropLibraryBackupArchive.swift \
  tests/LibrarySync/TropLibraryBackupArchiveChecks.swift \
  -o "$temp_dir/trop-library-backup-checks"
"$temp_dir/trop-library-backup-checks"

# Guard against accidental inclusion of credentials, stream URLs or raw DB
# serialization in the backup payload. Keep this as a narrow allowlist.
if grep -Eq 'SongEntity|DownloadedTrackEntity|EventEntity|SELECT \*|library_add_token|library_remove_token|playback_url|local_path' \
  Trop/Core/LibrarySync/TropLibraryBackupService.swift; then
  echo 'Backup source contains a prohibited field or raw-table export.'
  exit 1
fi

grep -Fq 'DatabaseService.shared.read' Trop/Core/LibrarySync/TropLibraryBackupService.swift
grep -Fq 'TropLibraryBackupArchive.inspect' Trop/Settings/TropLibraryBackupView.swift
grep -Fq 'SettingsNavigationRow("Library Backup"' Trop/Settings/SettingsView.swift
grep -Fq 'org.apoloengine.tropbackup' Trop/Resources/Info.plist

echo 'Trop portable backup source checks passed'
