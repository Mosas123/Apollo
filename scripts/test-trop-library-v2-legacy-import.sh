#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# The complete iOS project must still compile in Nightly. This fast guard
# parses the real Swift importer and exercises SQLite constraints with fixtures.
swiftc -frontend -parse Trop/Core/LibrarySync/TropLibraryV2LegacyImporter.swift

python3 - <<'PY'
import re
import sqlite3
from pathlib import Path

schema = Path("Trop/Database/DatabaseMigrations.swift").read_text()
registration = Path("Trop/Database/DatabaseService.swift").read_text()
importer = Path("Trop/Core/LibrarySync/TropLibraryV2LegacyImporter.swift").read_text()
assert 'registerMigration("v12", migrate: DatabaseMigrations.v12)' in registration
assert 'registerMigration("v13", migrate: DatabaseMigrations.v13)' in registration
assert "nonisolated let usesPersistentStore: Bool" in registration
assert "guard DatabaseService.shared.usesPersistentStore" in importer
assert "writeReturning { db in" in importer
assert "unresolvedLegacyMemberships(orphanCount)" in importer

v10 = schema.split("static let v10:", 1)[1].split("static let v11:", 1)[0]
v12 = schema.split("static let v12:", 1)[1].split("static let v13:", 1)[0]
v13 = schema.split("static let v13:", 1)[1].split("\n}", 1)[0]
queries = lambda part: re.findall(r'try db\.execute\(sql: """(.*?)"""\)', part, re.S)
assert len(queries(v10)) == 6
assert len(queries(v12)) == 2
assert len(queries(v13)) == 2

db = sqlite3.connect(":memory:")
db.execute("PRAGMA foreign_keys=ON")
db.execute("CREATE TABLE song (id TEXT PRIMARY KEY, title TEXT, liked INTEGER)")
db.execute("CREATE TABLE playlist (id TEXT PRIMARY KEY, name TEXT)")
db.execute("CREATE TABLE playlist_song_map (id INTEGER PRIMARY KEY, playlist_id TEXT, song_id TEXT, position INTEGER)")
db.execute("INSERT INTO song VALUES ('yt-a', 'Song A', 1)")
db.execute("INSERT INTO playlist VALUES ('list-a', 'Saved list')")
db.execute("INSERT INTO playlist_song_map VALUES (1, 'list-a', 'yt-a', 0)")
for query in queries(v10) + queries(v12) + queries(v13):
    db.execute(query)

for item_id, kind, title in [
    ("playlist-uuid", "playlist", "Saved list"),
    ("song-uuid", "recording", "Song A"),
    ("episode-uuid", "episode", "A saved episode"),
]:
    db.execute("""INSERT INTO trop_v2_item
       (id, kind, title, created_at, modified_at)
       VALUES (?, ?, ?, '2026-11-22', '2026-11-22')""", (item_id, kind, title))
db.execute("""INSERT INTO trop_v2_playlist_entry
    (id, playlist_id, recording_id, position, created_at)
    VALUES ('entry-uuid', 'playlist-uuid', 'song-uuid', 0, '2026-11-22')""")
db.execute("""INSERT INTO trop_v2_legacy_import_entry
    (legacy_membership_id, entry_id, imported_at)
    VALUES (1, 'entry-uuid', '2026-11-22')""")

assert db.execute("SELECT COUNT(*) FROM trop_v2_foreign_import_tombstone").fetchone()[0] == 0

# Retry must identify the same legacy membership, not append it twice.
assert db.execute("""SELECT entry_id FROM trop_v2_legacy_import_entry
    WHERE legacy_membership_id = 1""").fetchone() == ("entry-uuid",)
try:
    db.execute("""INSERT INTO trop_v2_legacy_import_entry
       VALUES (1, 'entry-uuid', '2026-11-22')""")
    raise AssertionError("Duplicate membership import accepted")
except sqlite3.IntegrityError:
    pass

# User deletion must remain possible, and a subsequent import should see a
# tombstone rather than resurrecting the removed song.
db.execute("DELETE FROM trop_v2_playlist_entry WHERE id='entry-uuid'")
assert db.execute("""SELECT entry_id FROM trop_v2_legacy_import_entry
    WHERE legacy_membership_id=1""").fetchone() == (None,)

db.execute("""INSERT INTO trop_v2_legacy_relation
    (id, owner_item_id, link_kind, external_id, created_at)
    VALUES ('relation-1', 'episode-uuid', 'episode_podcast',
            'yt-podcast', '2026-11-22')""")
try:
    db.execute("""INSERT INTO trop_v2_legacy_relation
        (id, owner_item_id, link_kind, external_id, created_at)
        VALUES ('relation-2', 'episode-uuid', 'episode_podcast',
                'wrong-podcast', '2026-11-22')""")
    raise AssertionError("Conflicting relation accepted")
except sqlite3.IntegrityError:
    pass

db.execute("DELETE FROM trop_v2_item WHERE id='episode-uuid'")
assert db.execute("SELECT COUNT(*) FROM trop_v2_legacy_relation").fetchone()[0] == 0

# No operation above may modify old library rows.
assert db.execute("SELECT id, liked FROM song").fetchall() == [("yt-a", 1)]
assert db.execute("SELECT id, name FROM playlist").fetchall() == [("list-a", "Saved list")]
assert db.execute("SELECT COUNT(*) FROM playlist_song_map").fetchone()[0] == 1

executable = "\\n".join(line for line in importer.splitlines()
                       if not line.lstrip().startswith("//"))
for forbidden in ["SyncBridge.", "InnerTubeClient.", "CookieStore.", "DELETE FROM",
                  "DROP TABLE", "playback_url", "local_path", "SELECT *"]:
    assert forbidden not in executable, f"Importer unexpectedly contains {forbidden}"
print("Trop V2 migration schema, tombstone, privacy and rollback guards passed")
PY
