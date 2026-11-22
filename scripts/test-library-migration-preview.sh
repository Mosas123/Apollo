#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import sqlite3

source = Path("Trop/Core/LibrarySync/TropLibraryMigrationPreview.swift").read_text()
dry_run = Path("Trop/Core/LibrarySync/TropLibraryV2MigrationDryRun.swift").read_text()
view = Path("Trop/Settings/TropLibraryMigrationPreviewView.swift").read_text()
settings = Path("Trop/Settings/SettingsView.swift").read_text()

assert "DatabaseService.shared.read" in source, "Inventory must be read-only"
for forbidden in ("dbPool.write", "DatabaseService.shared.write", "db.execute(",
                  "CKContainer.", "deleteAll", "DROP TABLE", "DELETE FROM", "UPDATE song"):
    assert forbidden not in source, f"Read-only migration preflight contains {forbidden}"
assert "DatabaseService.shared.read" in dry_run
assert "static func scan(in db: Database)" in dry_run
assert "TropLibraryV2MigrationDryRun.load()" in view
assert "Import blocked until conflicts are resolved" in view
assert "Nothing was imported" in view
for forbidden in ("DatabaseService.shared.write", "db.execute(", "DELETE FROM",
                  "DROP TABLE", "InnerTubeClient", "SyncBridge", "CKContainer."):
    assert forbidden not in dry_run, f"Dry-run forecast must not write or call providers: {forbidden}"
assert "TropLibraryMigrationPreviewView()" in settings
assert "No changes were made" in view
assert "Live iCloud syncing is not enabled yet" in view
assert "No files will be uploaded" in view

con = sqlite3.connect(":memory:")
con.executescript("""
CREATE TABLE song (id TEXT PRIMARY KEY, liked INTEGER);
CREATE TABLE album (id TEXT PRIMARY KEY, bookmarked_at TEXT);
CREATE TABLE artist (id TEXT PRIMARY KEY, bookmarked_at TEXT);
CREATE TABLE playlist (id TEXT PRIMARY KEY, bookmarked_at TEXT, browse_id TEXT);
CREATE TABLE playlist_song_map (playlist_id TEXT, song_id TEXT, position INTEGER);
CREATE TABLE podcast (id TEXT PRIMARY KEY, subscribed_at TEXT);
CREATE TABLE episode (id TEXT PRIMARY KEY, saved_at TEXT);
INSERT INTO song VALUES ('track-1', 1), ('track-2', 0);
INSERT INTO album VALUES ('album-1', 'saved'), ('album-2', NULL);
INSERT INTO artist VALUES ('artist-1', 'saved');
INSERT INTO playlist VALUES ('playlist-yt', 'saved', 'VLXYZ'), ('playlist-trop', 'saved', NULL);
INSERT INTO playlist_song_map VALUES ('playlist-yt', 'track-1', 0), ('playlist-trop', 'missing', 1);
INSERT INTO podcast VALUES ('podcast-1', 'saved');
INSERT INTO episode VALUES ('ep-1', 'saved'), ('ep-2', NULL);
""")

queries = {
"likedSongs": ("SELECT COUNT(*) FROM song WHERE liked = 1", 1),
"savedAlbums": ("SELECT COUNT(*) FROM album WHERE bookmarked_at IS NOT NULL", 1),
"followedArtists": ("SELECT COUNT(*) FROM artist WHERE bookmarked_at IS NOT NULL", 1),
"savedPlaylists": ("SELECT COUNT(*) FROM playlist WHERE bookmarked_at IS NOT NULL", 2),
"youtubeLinkedPlaylists": ("SELECT COUNT(*) FROM playlist WHERE bookmarked_at IS NOT NULL AND browse_id IS NOT NULL", 1),
"playlistMemberships": ("SELECT COUNT(*) FROM playlist_song_map", 2),
"followedPodcasts": ("SELECT COUNT(*) FROM podcast WHERE subscribed_at IS NOT NULL", 1),
"savedEpisodes": ("SELECT COUNT(*) FROM episode WHERE saved_at IS NOT NULL", 1),
}
for key, (query, expected) in queries.items():
    assert query in source, f"{key} source query missing"
    assert con.execute(query).fetchone()[0] == expected, key
orphans = """
SELECT COUNT(*) FROM playlist_song_map AS membership
LEFT JOIN playlist ON playlist.id = membership.playlist_id
LEFT JOIN song ON song.id = membership.song_id
WHERE playlist.id IS NULL OR song.id IS NULL
"""
assert "LEFT JOIN playlist ON playlist.id = membership.playlist_id" in source
assert "LEFT JOIN song ON song.id = membership.song_id" in source
assert con.execute(orphans).fetchone()[0] == 1
print("Library migration read-only inventory checks passed")
PY
