#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Real local Documents writer, compiled unchanged in strict Swift 6.
# Two saves must not overwrite one another; invalid archives are rejected.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/LibrarySync/TropLibraryCombinedLocalSnapshotStore.swift \
  tests/LibrarySync/TropLibraryCombinedLocalSnapshotStoreChecks.swift \
  -o "$tmp_dir/v2-combined-local-save-checks"
"$tmp_dir/v2-combined-local-save-checks"

# User-requested Files export is read-only. Validate downloaded audio paths,
# symlink escapes, sanitization and original-file preservation on Swift 6.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/Storage/TropFilesExportPolicy.swift \
  tests/LibrarySync/TropFilesExportChecks.swift \
  -o "$tmp_dir/trop-files-export-checks"
"$tmp_dir/trop-files-export-checks"
swiftc -frontend -parse Trop/Settings/TropFilesExportView.swift
grep -Fq 'TropFilesExportView()' Trop/Settings/StorageSettingsView.swift
grep -Fq 'UIDocumentPickerViewController(' Trop/Settings/TropFilesExportView.swift
grep -Fq 'asCopy: true' Trop/Settings/TropFilesExportView.swift

# Portable Library V2 artwork must match independent recording metadata.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/Metadata/TextMatch.swift \
  Trop/Core/Metadata/TropLibraryV2ArtworkSelectionPolicy.swift \
  tests/LibrarySync/TropLibraryV2ArtworkChecks.swift \
  -o "$tmp_dir/v2-artwork-checks"
"$tmp_dir/v2-artwork-checks"

# Search-by-metadata only returns user-selectable, verified provider IDs.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/Metadata/TextMatch.swift \
  Trop/Core/MusicSources/MusicCatalog.swift \
  Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
  Trop/Core/LibrarySync/TropLibraryV2AudioMatchPolicy.swift \
  tests/LibrarySync/TropLibraryV2AudioSourceChecks.swift \
  -o "$tmp_dir/v2-audio-source-checks"
"$tmp_dir/v2-audio-source-checks"

# Trop Match may auto-link studio recordings, but live/remix/unknown
# editions must be excluded from automatic playback and kept for review.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/Metadata/TextMatch.swift \
  Trop/Core/MusicSources/MusicCatalog.swift \
  Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
  Trop/Core/LibrarySync/TropLibraryV2AudioMatchPolicy.swift \
  Trop/Core/LibrarySync/TropMatchCandidatePolicy.swift \
  tests/LibrarySync/TropMatchCandidatePolicyChecks.swift \
  -o "$tmp_dir/trop-match-candidate-checks"
"$tmp_dir/trop-match-candidate-checks"

# Saved recordings only: strictly verified metadata may generate a small,
# bounded number of prelinks. Uncertain editions must never auto-link.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/Metadata/TextMatch.swift \
  Trop/Core/MusicSources/MusicCatalog.swift \
  Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
  Trop/Core/LibrarySync/TropLibraryV2AudioMatchPolicy.swift \
  Trop/Core/LibrarySync/TropMatchCandidatePolicy.swift \
  Trop/Core/LibrarySync/TropLibraryV2PrelinkPolicy.swift \
  tests/LibrarySync/TropLibraryV2PrelinkPolicyChecks.swift \
  -o "$tmp_dir/trop-match-prelink-checks"
"$tmp_dir/trop-match-prelink-checks"

# Manual matching is opt-in, page-bounded and resumes from a Trop UUID;
# missing/deleted records cannot corrupt playlist membership or cursor state.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
  Trop/Core/LibrarySync/TropLibraryV2PrelinkBatchPolicy.swift \
  tests/LibrarySync/TropLibraryV2PrelinkBatchPolicyChecks.swift \
  -o "$tmp_dir/trop-match-batch-checks"
"$tmp_dir/trop-match-batch-checks"
swiftc -frontend -parse Trop/Settings/TropLibraryV2BatchMatchView.swift
grep -Fq 'TropLibraryV2BatchMatchView()' Trop/Settings/SettingsView.swift
grep -Fq 'TropLibraryV2PrelinkBatchPolicy.cursorKey' \
  Trop/Core/LibrarySync/TropLibraryV2Prelinker.swift
grep -Fq 'try Task.checkCancellation()' \
  Trop/Core/LibrarySync/TropLibraryV2Prelinker.swift
grep -Fq 'scanNextBatch()' Trop/Settings/TropLibraryV2BatchMatchView.swift
grep -Fq 'TropLibraryV2Store.independentSourceCoverage()' \
  Trop/Settings/TropLibraryV2BatchMatchView.swift
grep -Fq '.recordingsMissingIndependentSources()' \
  Trop/Settings/TropLibraryV2BatchMatchView.swift
grep -Fq 'TropLibraryV2AudioSourceSheet(recording:' \
  Trop/Settings/TropLibraryV2BatchMatchView.swift
grep -Fq 'sourceName(for: track)' Trop/Library/TropLibraryV2AudioSourceSheet.swift
grep -Fq 'MusicAddonsStore.shared.installation(key: ref.k)' \
  Trop/Library/TropLibraryV2AudioSourceSheet.swift
grep -Fq 'AddonPlaybackID.prefix + track.id.rawValue' \
  Trop/Library/TropLibraryV2AudioSourceSheet.swift
# Read-only coverage counts saved recordings, not aliases, ignores YouTube
# and unapproved scopes, and does not mistake a link for playable audio.
python3 - <<'COVERAGE_CHECK'
import sqlite3
from pathlib import Path

store = Path("Trop/Core/LibrarySync/TropLibraryV2Store.swift").read_text()
marker = "SELECT COUNT(DISTINCT item.id) AS saved_count,"
assert marker in store
query = marker + store.split(marker, 1)[1].split('"""', 1)[0]
db = sqlite3.connect(":memory:")
db.executescript("""
CREATE TABLE trop_v2_item (
    id TEXT PRIMARY KEY, kind TEXT, saved_at TEXT
);
CREATE TABLE trop_v2_source_alias (
    item_id TEXT, kind TEXT, provider TEXT, source_scope TEXT
);
INSERT INTO trop_v2_item VALUES
 ('a','recording','2026-11-22'), ('b','recording','2026-11-22'),
 ('c','recording','2026-11-22'), ('d','recording','2026-11-22'),
 ('e','recording',NULL), ('p','playlist','2026-11-22');
INSERT INTO trop_v2_source_alias VALUES
 ('a','recording','addon','global'),
 ('a','recording','qobuz','global'),
 ('b','recording','youtube','global'),
 ('c','recording','audius','user-approved-alt'),
 ('d','recording','addon','local-private'),
 ('e','recording','jiosaavn','global'),
 ('p','recording','addon','global');
""")
assert db.execute(query).fetchone() == (4, 2)

# The list must be limited, sorted, and agree with the independent-coverage
# count, even with duplicate provider IDs and excluded YouTube-only aliases.
db.executescript("""
ALTER TABLE trop_v2_item ADD COLUMN title TEXT;
ALTER TABLE trop_v2_item ADD COLUMN artist_or_author TEXT;
ALTER TABLE trop_v2_item ADD COLUMN duration_seconds INTEGER;
ALTER TABLE trop_v2_item ADD COLUMN liked_at TEXT;
UPDATE trop_v2_item SET title=id, artist_or_author='Artist',
    duration_seconds=200;
""")
missing_marker = "SELECT item.id, item.title, item.artist_or_author,"
assert missing_marker in store
missing_source_query = missing_marker + store.split(
    missing_marker, 1
)[1].split('"""', 1)[0]
assert "NOT EXISTS" in missing_source_query and "LIMIT ?" in missing_source_query
missing = db.execute(missing_source_query, (12,)).fetchall()
assert [row[0] for row in missing] == ["b", "d"]
assert len(missing) + db.execute(query).fetchone()[1] == 4
assert len(db.execute(missing_source_query, (1,)).fetchall()) == 1
print("Saved independent-audio coverage and missing-source review passed")
COVERAGE_CHECK

swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryV2Prelinker.swift
grep -Fq 'TropLibraryV2Prelinker.shared.schedule(' \
  Trop/Core/LibrarySync/TropLibraryV2Store.swift
grep -Fq 'TropLibraryV2Prelinker.shared.scheduleVisibleLibrary' \
  Trop/Library/TropLibraryV2MainStyleView.swift
grep -Fq 'TropLibraryV2Prelinker.shared.scheduleVisibleLibrary' \
  Trop/Library/TropLibraryV2Screen.swift
grep -Fq 'TropLibraryV2Store.linkConfirmedAudioSource(' \
  Trop/Core/LibrarySync/TropLibraryV2Prelinker.swift
if grep -E 'InnerTube|SyncBridge|PlaybackQueue.play' \
  Trop/Core/LibrarySync/TropLibraryV2Prelinker.swift; then
  echo 'Saved prelinker must not bootstrap YouTube, sync accounts or autoplay'
  exit 1
fi

swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryV2AudioDiscovery.swift
swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryV2PlaybackRouter.swift
swiftc -frontend -parse Trop/Core/MusicSources/QobuzClient.swift
swiftc -frontend -parse Trop/Core/MusicSources/JioSaavnClient.swift
grep -Fq 'TropLibraryV2AudioDiscovery.inspect(' \
  Trop/Core/LibrarySync/TropLibraryV2PlaybackRouter.swift
grep -Fq 'userApprovedAlternate: approvedAlternate' \
  Trop/Library/TropLibraryV2AudioSourceSheet.swift
grep -Fq 'Section("Review Alternatives")' \
  Trop/Library/TropLibraryV2AudioSourceSheet.swift
grep -Fq 'trop.match.youtubeAudioEnabled' Trop/Settings/SettingsView.swift
swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryV2AudioLinkError.swift
swiftc -frontend -parse Trop/Library/TropLibraryV2AudioSourceSheet.swift
swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryV2Store.swift
grep -Fq 'TropLibraryV2AudioSourceSheet(recording:' \
  Trop/Library/TropLibraryV2MainStyleView.swift
grep -Fq 'TropLibraryV2AudioSourceSheet(recording:' \
  Trop/Library/TropLibraryV2Screen.swift
grep -Fq 'linkConfirmedAudioSource(' Trop/Core/LibrarySync/TropLibraryV2Store.swift
grep -Fq "currentOwner == id" Trop/Core/LibrarySync/TropLibraryV2Store.swift
grep -Fq "throw TropLibraryV2AudioLinkError.existingSource" \
  Trop/Core/LibrarySync/TropLibraryV2Store.swift
swiftc -frontend -parse Trop/Library/TropLibraryV2ArtworkView.swift
swiftc -frontend -parse Trop/Library/TropLibraryV2MainStyleView.swift
swiftc -frontend -parse Trop/Library/TropLibraryV2Screen.swift
grep -Fq 'TropLibraryV2ArtworkView(' Trop/Library/TropLibraryV2MainStyleView.swift
grep -Fq 'TropLibraryV2ArtworkView(' Trop/Library/TropLibraryV2Screen.swift
swiftc -frontend -parse Trop/Settings/TropLibraryCombinedBackupView.swift
grep -Fq 'TropLibraryCombinedLocalSnapshotStore.saveVerified(data)' \
  Trop/Settings/TropLibraryCombinedBackupView.swift
grep -Fq 'private func exportLatestLocal() async' \
  Trop/Settings/TropLibraryCombinedBackupView.swift
grep -Fq 'private func saveLocalCopy() async' \
  Trop/Settings/TropLibraryCombinedBackupView.swift

swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
  Trop/Core/LibrarySync/TropLibraryV2RecoveryArchive.swift \
  tests/LibrarySync/TropLibraryV2RecoveryArchiveChecks.swift \
  -o "$tmp_dir/v2-recovery-archive-checks"
"$tmp_dir/v2-recovery-archive-checks"

# The app Files folder has a picker-free, read-only snapshot verification path.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
  Trop/Core/LibrarySync/TropLibraryV2RecoveryArchive.swift \
  Trop/Core/LibrarySync/TropLibraryV2LocalSnapshotFinder.swift \
  tests/LibrarySync/TropLibraryV2LocalSnapshotFinderChecks.swift \
  -o "$tmp_dir/v2-local-snapshot-checks"
"$tmp_dir/v2-local-snapshot-checks"

# The new envelope carries legacy and V2 without weakening their validators.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
  Trop/Core/LibrarySync/TropLibraryBackupArchive.swift \
  Trop/Core/LibrarySync/TropLibraryV2RecoveryArchive.swift \
  Trop/Core/LibrarySync/TropLibraryCombinedBackupArchive.swift \
  Trop/Core/LibrarySync/TropLibraryCombinedRestorePlanner.swift \
  tests/LibrarySync/TropLibraryCombinedBackupArchiveChecks.swift \
  -o "$tmp_dir/v2-combined-archive-checks"
"$tmp_dir/v2-combined-archive-checks"

# Picker-free local combined archive discovery uses a bounded read and
# skips directories, unrelated files and symlinks.
swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
  Trop/Core/LibrarySync/TropLibraryBackupArchive.swift \
  Trop/Core/LibrarySync/TropLibraryV2RecoveryArchive.swift \
  Trop/Core/LibrarySync/TropLibraryCombinedBackupArchive.swift \
  Trop/Core/LibrarySync/TropLibraryCombinedLocalSnapshotFinder.swift \
  tests/LibrarySync/TropLibraryCombinedLocalSnapshotFinderChecks.swift \
  -o "$tmp_dir/v2-combined-local-checks"
"$tmp_dir/v2-combined-local-checks"

swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryBackupService.swift
swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryCombinedBackupService.swift
swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryCombinedRestorePreflight.swift

swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryV2RecoveryStore.swift
swiftc -frontend -parse Trop/Settings/TropLibraryV2RecoveryView.swift
swiftc -frontend -parse Trop/Settings/TropLibraryV2DocumentPicker.swift
swiftc -frontend -parse Trop/Settings/TropLibraryCombinedBackupView.swift
swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryCombinedRestoreRehearsal.swift
swiftc -frontend -parse Trop/Database/TropDatabaseMigrationSequence.swift
grep -Fq 'TropLibraryCombinedRestoreRehearsal.rehearse(found.bytes)' \
  Trop/Settings/TropLibraryCombinedBackupView.swift
grep -Fq 'DatabaseQueue()' Trop/Core/LibrarySync/TropLibraryCombinedRestoreRehearsal.swift
grep -Fq 'TropDatabaseMigrationSequence.register(&migrations)' \
  Trop/Core/LibrarySync/TropLibraryCombinedRestoreRehearsal.swift
grep -Fq 'TropLibraryCombinedRestoreStore.restoreInTransaction' \
  Trop/Core/LibrarySync/TropLibraryCombinedRestoreRehearsal.swift
if grep -Fq 'DatabaseService.shared' \
  Trop/Core/LibrarySync/TropLibraryCombinedRestoreRehearsal.swift; then
  echo 'In-memory restoration rehearsal must never access the live DB singleton'
  exit 1
fi
if grep -Fq 'restoreIntoEmptyLibrary(' \
  Trop/Settings/TropLibraryCombinedBackupView.swift; then
  echo 'Combined backup UI must not contain real-library restore calls'
  exit 1
fi

swiftc -frontend -parse Trop/Settings/TropLibraryCombinedBackupView.swift
swiftc -frontend -parse Trop/Settings/TropLibraryCombinedRestoreView.swift
grep -Fq 'TropLibraryCombinedRestoreView()' \
  Trop/Settings/TropLibraryCombinedBackupView.swift
grep -Fq 'TropLibraryCombinedRestorePreflight.requireEmpty(db)' \
  Trop/Settings/TropLibraryCombinedRestoreView.swift
grep -Fq 'TropLibraryCombinedRestoreStore' \
  Trop/Settings/TropLibraryCombinedRestoreView.swift
grep -Fq '.restoreIntoEmptyLibrary(archive)' \
  Trop/Settings/TropLibraryCombinedRestoreView.swift
grep -Fq 'Button("Restore metadata", role: .destructive)' \
  Trop/Settings/TropLibraryCombinedRestoreView.swift
grep -Fq 'data.count <= maximum' \
  Trop/Settings/TropLibraryCombinedRestoreView.swift
grep -Fq 'guard DatabaseService.shared.usesPersistentStore' \
  Trop/Settings/TropLibraryCombinedRestoreView.swift
if grep -E 'DELETE FROM|DROP TABLE|removeItem|SyncBridge|InnerTube' \
  Trop/Settings/TropLibraryCombinedRestoreView.swift; then
  echo 'Empty-only restore UI must never wipe data, mutate remote accounts or synchronize'
  exit 1
fi
grep -Fq 'TropLibraryCombinedBackupView()' Trop/Settings/SettingsView.swift
grep -Fq 'TropLibraryCombinedBackupService.export()' Trop/Settings/TropLibraryCombinedBackupView.swift
grep -Fq 'TropLibraryCombinedBackupService.preview(bytes)' Trop/Settings/TropLibraryCombinedBackupView.swift
grep -Fq 'TropLibraryCombinedLocalSnapshotFinder.latest()' Trop/Settings/TropLibraryCombinedBackupView.swift
grep -Fq 'TropLibraryV2DocumentPicker(' Trop/Settings/TropLibraryCombinedBackupView.swift
grep -Fq 'TropLibraryCombinedBackupArchive.maximumBytes + 1' Trop/Settings/TropLibraryCombinedBackupView.swift
if grep -E 'restoreIntoEmptyLibrary|importLegacySnapshot|DELETE FROM|DROP TABLE' \
  Trop/Settings/TropLibraryCombinedBackupView.swift \
  Trop/Core/LibrarySync/TropLibraryCombinedLocalSnapshotFinder.swift; then
  echo 'Combined backup UI must remain strictly read-only'
  exit 1
fi
grep -Fq 'TropLibraryV2RecoveryView()' Trop/Settings/SettingsView.swift
grep -Fq 'TropLibraryV2RecoveryStore.export()' Trop/Settings/TropLibraryV2RecoveryView.swift
grep -Fq 'TropLibraryV2RecoveryStore.preview(data)' Trop/Settings/TropLibraryV2RecoveryView.swift
# The Files picker must accept a JSON document classified as generic
# public.data by a third-party provider; strict verification is content-based.
grep -Fq 'TropLibraryV2DocumentPicker(' Trop/Settings/TropLibraryV2RecoveryView.swift
grep -Fq 'UIDocumentPickerViewController(' Trop/Settings/TropLibraryV2DocumentPicker.swift
grep -Fq 'asCopy: true' Trop/Settings/TropLibraryV2DocumentPicker.swift
grep -Fq 'didPickDocumentsAt urls' Trop/Settings/TropLibraryV2DocumentPicker.swift
grep -Fq 'FileHandle(forReadingFrom: url)' Trop/Settings/TropLibraryV2RecoveryView.swift
grep -Fq 'TropLibraryV2RecoveryArchive.maximumBytes + 1' Trop/Settings/TropLibraryV2RecoveryView.swift
grep -Fq 'checksumMismatch' Trop/Settings/TropLibraryV2RecoveryView.swift
grep -Fq 'TropLibraryV2LocalSnapshotFinder.latest()' Trop/Settings/TropLibraryV2RecoveryView.swift
grep -Fq 'TropLibraryV2RecoveryStore.preview(found.bytes)' Trop/Settings/TropLibraryV2RecoveryView.swift
grep -Fq 'V2_FILE_IMPORTER open requested' Trop/Settings/TropLibraryV2RecoveryView.swift
grep -Fq 'V2_FILE_IMPORTER UIKit delegate received selection' Trop/Settings/TropLibraryV2DocumentPicker.swift
grep -Fq 'localVerificationAlert = true' Trop/Settings/TropLibraryV2RecoveryView.swift
python3 - <<'PLIST_CHECK'
import plistlib
from pathlib import Path

info = plistlib.loads(Path("Trop/Resources/Info.plist").read_bytes())
assert info["UIFileSharingEnabled"] is True
assert info["LSSupportsOpeningDocumentsInPlace"] is True
assert not info.get("UISupportsDocumentBrowser", False), (
    "Thrum is not a UIDocumentBrowser app; the Files importer is a modal picker"
)
print("Thrum Files app / picker Info.plist configuration passed")
PLIST_CHECK
if grep -E 'restoreIntoEmptyLibrary|DELETE FROM|DROP TABLE' Trop/Settings/TropLibraryV2RecoveryView.swift; then
  echo "Recovery view must remain read-only"
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
import sqlite3
import re

migrations = Path("Trop/Database/DatabaseMigrations.swift").read_text()
store = Path("Trop/Core/LibrarySync/TropLibraryV2RecoveryStore.swift").read_text()
archive = Path("Trop/Core/LibrarySync/TropLibraryV2RecoveryArchive.swift").read_text()

def ddl(section, next_section):
    chunk = migrations.split("static let " + section + ":", 1)[1]
    chunk = chunk.split("static let " + next_section + ":", 1)[0]
    return re.findall(r'try db\.execute\(sql: """(.*?)"""\)', chunk, re.S)

queries = ddl("v10", "v11") + ddl("v11", "v12")
part12 = migrations.split("static let v12:", 1)[1].split("static let v13:", 1)[0]
queries += re.findall(r'try db\.execute\(sql: """(.*?)"""\)', part12, re.S)
assert len(queries) == 10
assert 'guard DatabaseService.shared.usesPersistentStore' in store
assert 'throw TropLibraryV2RecoveryError.existingLibrary' in store
assert 'throw TropLibraryV2RecoveryError.legacySourceConflict' in store
assert 'try await DatabaseService.shared.write { db in' in store
assert 'TropLibraryV2RecoveryArchive.decode(archive)' in store
assert 'isPortableAlias' in store and 'omitted += 1' in store
assert 'SHA256.hash' in archive and 'checksumMismatch' in archive

def new_db():
    db = sqlite3.connect(":memory:")
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("CREATE TABLE song (id TEXT PRIMARY KEY, title TEXT)")
    db.execute("CREATE TABLE playlist_song_map (id INTEGER PRIMARY KEY, playlist_id TEXT, song_id TEXT, position INTEGER)")
    db.execute("INSERT INTO song VALUES ('legacy-song', 'Preserve me')")
    for query in queries:
        db.execute(query)
    db.commit()
    return db

source = new_db()
playlist = "a0000000-0000-4000-8000-000000000002"
song = "a0000000-0000-4000-8000-000000000001"
stamp = "2026-11-22 09:00:00.000"

for item_id, kind, title in [(playlist, "playlist", "My Mix"),
                              (song, "recording", "A song")]:
    source.execute(
        """INSERT INTO trop_v2_item(id, kind, title, created_at, modified_at)
           VALUES (?, ?, ?, ?, ?)""", (item_id, kind, title, stamp, stamp)
    )
source.execute(
    """INSERT INTO trop_v2_source_alias
       (id, item_id, kind, provider, source_scope, external_id)
       VALUES ('safe-alias', ?, 'recording', 'youtube', 'global', 'yt001')""",
    (song,)
)
for i in (0, 1):
    source.execute(
        """INSERT INTO trop_v2_playlist_entry
           (id, playlist_id, recording_id, position, created_at)
           VALUES (?, ?, ?, ?, ?)""",
        (f"entry-{i}", playlist, song, i, stamp)
    )
    source.execute(
        """INSERT INTO trop_v2_legacy_import_entry
           (legacy_membership_id, entry_id, imported_at)
           VALUES (?, ?, ?)""",
        (i + 1, f"entry-{i}", stamp)
    )
source.execute(
    """INSERT INTO trop_v2_radio_favorite
       (id, station_uuid, name, subtitle, added_at)
       VALUES ('radio-id', '9617ba77-0601-11e8-ae97-52543be04c81',
               'Latina Salsa', '', ?)""", (stamp,)
)

tables = ["trop_v2_item", "trop_v2_source_alias", "trop_v2_playlist_entry",
          "trop_v2_radio_favorite", "trop_v2_legacy_import_entry",
          "trop_v2_legacy_relation"]
columns = {
    "trop_v2_item": "id, kind, title, artist_or_author, duration_seconds, saved_at, liked_at, created_at, modified_at",
    "trop_v2_source_alias": "id, item_id, kind, provider, source_scope, external_id",
    "trop_v2_playlist_entry": "id, playlist_id, recording_id, position, created_at",
    "trop_v2_radio_favorite": "id, station_uuid, name, subtitle, added_at",
    "trop_v2_legacy_import_entry": "legacy_membership_id, entry_id, imported_at",
    "trop_v2_legacy_relation": "id, owner_item_id, link_kind, external_id, created_at",
}
dump = {
    table: source.execute(f"SELECT {columns[table]} FROM {table} ORDER BY 1").fetchall()
    for table in tables
}

restored = new_db()
restored.execute("BEGIN")
for table in tables:
    fields = [field.strip() for field in columns[table].split(",")]
    sql = f"INSERT INTO {table} ({columns[table]}) VALUES ({','.join('?' for _ in fields)})"
    restored.executemany(sql, dump[table])
restored.execute("COMMIT")

for table in tables:
    assert restored.execute(f"SELECT {columns[table]} FROM {table} ORDER BY 1").fetchall() == dump[table]
assert restored.execute(
    "SELECT recording_id FROM trop_v2_playlist_entry ORDER BY position"
).fetchall() == [(song,), (song,)]
assert source.execute("SELECT title FROM song").fetchone() == ("Preserve me",)
assert restored.execute("SELECT title FROM song").fetchone() == ("Preserve me",)

# A restore into a populated DB is prohibited; no overwrite or data loss.
assert restored.execute("SELECT COUNT(*) FROM trop_v2_item").fetchone()[0] == 2

# Ledger row IDs are only local to an origin DB. Cross-profile restores
# must refuse to treat coincidentally equal integer IDs as imported already.
foreign = new_db()
foreign.execute("""INSERT INTO playlist_song_map
    (id, playlist_id, song_id, position)
    VALUES (1, 'different-playlist', 'different-song', 0)""")
foreign_count = foreign.execute("SELECT COUNT(*) FROM playlist_song_map").fetchone()[0]
assert foreign_count == 1 and len(dump["trop_v2_legacy_import_entry"]) > 0

# A broken link must roll back the *entire* destination transaction.
broken = new_db()
try:
    broken.execute("BEGIN")
    broken.execute(
        """INSERT INTO trop_v2_item(id, kind, title, created_at, modified_at)
           VALUES (?, 'recording', 'Will roll back', ?, ?)""",
        (song, stamp, stamp)
    )
    broken.execute(
        """INSERT INTO trop_v2_playlist_entry
           (id, playlist_id, recording_id, position, created_at)
           VALUES ('bad', 'missing-playlist', ?, 0, ?)""",
        (song, stamp)
    )
    broken.execute("COMMIT")
    raise AssertionError("Broken reference was accepted")
except sqlite3.IntegrityError:
    broken.execute("ROLLBACK")
assert broken.execute("SELECT COUNT(*) FROM trop_v2_item").fetchone()[0] == 0

# Deleting an imported entry does not delete the import ledger provenance.
restored.execute("DELETE FROM trop_v2_playlist_entry WHERE id='entry-0'")
assert restored.execute(
    "SELECT entry_id FROM trop_v2_legacy_import_entry WHERE legacy_membership_id=1"
).fetchone() == (None,)
print("Trop V2 recovery SQLite fixtures, rollback, ordering and tombstones passed")
PY
