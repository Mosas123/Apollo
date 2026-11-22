#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Execute v11 against legacy and V2 fixture rows: adding favorites must
# never delete music or store radio stream URLs in a local preference.
python3 - <<'PY'
from pathlib import Path
import re
import sqlite3

migration = Path("Trop/Database/DatabaseMigrations.swift").read_text()
v11 = migration.split("static let v11:", 1)
assert len(v11) == 2
queries = re.findall(r'try db\.execute\(sql: """(.*?)"""\)', v11[1], re.S)
assert len(queries) == 2, f"Expected 2 statements for v11, got {len(queries)}"
assert 'registerMigration("v11", migrate: DatabaseMigrations.v11)' in Path(
    "Trop/Database/DatabaseService.swift"
).read_text()

db = sqlite3.connect(":memory:")
db.execute("CREATE TABLE song (id TEXT PRIMARY KEY, liked INTEGER)")
db.execute("INSERT INTO song VALUES ('old-favorite', 1)")
db.execute("CREATE TABLE trop_v2_item (id TEXT PRIMARY KEY, title TEXT)")
db.execute("INSERT INTO trop_v2_item VALUES ('v2-song', 'Song')")
for query in queries:
    db.execute(query)
assert db.execute("SELECT COUNT(*) FROM trop_v2_radio_favorite").fetchone()[0] == 0
db.execute("""
    INSERT INTO trop_v2_radio_favorite(id, station_uuid, name, subtitle, added_at)
    VALUES('local-uuid-1', '00000000-0000-4000-8000-000000000001',
           'Radio Paradise', 'USA', '2026-11-22')
""")
try:
    db.execute("""
        INSERT INTO trop_v2_radio_favorite(id, station_uuid, name, subtitle, added_at)
        VALUES('local-uuid-2', '00000000-0000-4000-8000-000000000001',
               'Duplicate', 'USA', '2026-11-22')
    """)
    raise AssertionError("Duplicate station favorite was accepted")
except sqlite3.IntegrityError:
    pass
db.execute("DELETE FROM trop_v2_radio_favorite WHERE station_uuid = ?",
           ('00000000-0000-4000-8000-000000000001',))
assert db.execute("SELECT COUNT(*) FROM trop_v2_radio_favorite").fetchone()[0] == 0
assert db.execute("SELECT liked FROM song WHERE id = 'old-favorite'").fetchone() == (1,)
assert db.execute("SELECT title FROM trop_v2_item WHERE id = 'v2-song'").fetchone() == ("Song",)
columns = [x[1] for x in db.execute("PRAGMA table_info(trop_v2_radio_favorite)")]
assert "stream_url" not in columns and "url" not in columns
print("V2 radio favorites schema and legacy isolation passed")
PY

grep -Fq 'TropLibraryV2RadioStore.save(station:' Trop/Features/Radio/RadioView.swift
grep -Fq 'TropLibraryV2RadioStore.remove(stationUUID:' Trop/Features/Radio/RadioView.swift
grep -Fq 'TropLibraryV2RadioStore.favorites()' Trop/Library/TropLibraryV2Screen.swift
grep -Fq 'RadioPlaybackCoordinator.playSaved' Trop/Library/TropLibraryV2Screen.swift
grep -Fq '/json/stations/byuuid/' Trop/Core/Radio/RadioBrowser.swift
grep -Fq 'guard generation == NowPlaying.shared.playbackGeneration' \
  Trop/Core/Radio/RadioPlaybackCoordinator.swift

# The model and its DDL must not contain an audio URL or credentials.
if grep -Ei 'signed.url|stream_url|playback_url|cookie|credential' \
  Trop/Database/DatabaseMigrations.swift | grep -F 'trop_v2_radio_favorite'; then
  echo 'Unsafe radio favorites schema'
  exit 1
fi
echo "V2 radio favorites wiring checks passed"
