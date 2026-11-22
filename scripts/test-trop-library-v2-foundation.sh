#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete \
  Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
  tests/LibrarySync/TropLibraryV2IdentityChecks.swift \
  -o "$temp_dir/trop-library-v2-checks"
"$temp_dir/trop-library-v2-checks"

# Exercise the exact v10 SQL on a legacy library fixture in SQLite. This
# does not require a real user's data, a YouTube account or iCloud credentials.
python3 - <<'PY'
from pathlib import Path
import re
import sqlite3

migrations = Path("Trop/Database/DatabaseMigrations.swift").read_text()
part = migrations.split("static let v10:", 1)
assert len(part) == 2, "Missing v10 schema"
queries = re.findall(r'try db\.execute\(sql: """(.*?)"""\)', part[1], re.S)
assert len(queries) == 6, f"Expected 6 additive schema statements: {len(queries)}"
assert 'registerMigration("v10", migrate: DatabaseMigrations.v10)' in Path(
    "Trop/Database/DatabaseService.swift"
).read_text()

db = sqlite3.connect(":memory:")
db.execute("PRAGMA foreign_keys=ON")
db.execute("CREATE TABLE song (id TEXT PRIMARY KEY, liked INTEGER)")
db.execute("CREATE TABLE playlist (id TEXT PRIMARY KEY, name TEXT)")
db.execute("INSERT INTO song VALUES ('legacy-song', 1)")
db.execute("INSERT INTO playlist VALUES ('legacy-playlist', 'Keep me')")
for sql in queries:
    db.execute(sql)

assert db.execute("SELECT id, liked FROM song").fetchall() == [("legacy-song", 1)]
assert db.execute("SELECT id, name FROM playlist").fetchall() == [("legacy-playlist", "Keep me")]
assert db.execute("SELECT count(*) FROM trop_v2_item").fetchone()[0] == 0

items = [
    ("recording-uuid", "recording", "A song"),
    ("playlist-uuid", "playlist", "New playlist"),
]
for item_id, kind, title in items:
    db.execute(
        """INSERT INTO trop_v2_item
           (id, kind, title, created_at, modified_at)
           VALUES (?, ?, ?, '2026-11-22', '2026-11-22')""",
        (item_id, kind, title)
    )

# Same song can appear twice: individual membership UUIDs are authoritative.
for number in range(2):
    db.execute(
        """INSERT INTO trop_v2_playlist_entry
           (id, playlist_id, recording_id, position, created_at)
           VALUES (?, ?, ?, ?, '2026-11-22')""",
        (f"membership-{number}", "playlist-uuid", "recording-uuid", number)
    )
assert db.execute(
    "SELECT recording_id FROM trop_v2_playlist_entry ORDER BY position"
).fetchall() == [("recording-uuid",), ("recording-uuid",)]

db.execute(
    """INSERT INTO trop_v2_source_alias
       (id, item_id, kind, provider, source_scope, external_id)
       VALUES ('alias-1', 'recording-uuid', 'recording', 'spotify', 'global', 'abc')"""
)
try:
    db.execute(
        """INSERT INTO trop_v2_source_alias
           (id, item_id, kind, provider, source_scope, external_id)
           VALUES ('alias-2', 'recording-uuid', 'recording', 'spotify', 'global', 'abc')"""
    )
    raise AssertionError("Duplicate provider alias was accepted")
except sqlite3.IntegrityError:
    pass

try:
    db.execute(
        """INSERT INTO trop_v2_playlist_entry
           (id, playlist_id, recording_id, position, created_at)
           VALUES ('bad', 'playlist-uuid', 'missing-recording', 2, '2026-11-22')"""
    )
    raise AssertionError("Invalid membership reference was accepted")
except sqlite3.IntegrityError:
    pass

assert db.execute("SELECT count(*) FROM trop_v2_playlist_entry").fetchone()[0] == 2
assert db.execute("SELECT count(*) FROM song").fetchone()[0] == 1
print("Trop Library V2 additive SQLite schema checks passed")
PY

# The new store must never invoke remote YouTube mutations or read legacy tables.
if grep -vE '^[[:space:]]*//' Trop/Core/LibrarySync/TropLibraryV2Store.swift \
  | grep -E 'InnerTube|SyncBridge|CookieStore|DELETE FROM|DROP TABLE|MutationService'; then
  echo "V2 store unexpectedly depends on legacy sync or destructive SQL"
  exit 1
fi
echo "Trop Library V2 source isolation checks passed"
