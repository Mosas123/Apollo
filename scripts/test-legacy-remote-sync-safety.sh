#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
src=Path("Trop/Services/TropLibraryStore.swift").read_text()
expected=[
    ("applyArtistSync", "applyPlaylistSync"),
    ("applyPlaylistSync", "applyAlbumSync"),
    ("applyAlbumSync", "applyPodcastSync"),
    ("applyPodcastSync", "// MARK: - Liked songs"),
]
for start,end in expected:
    begin=src.index("func " + start + "(")
    finish=src.index(("func " + end + "(") if not end.startswith("//") else end, begin)
    body=src[begin:finish]
    assert "SET bookmarked_at = NULL" not in body, start
    assert "SET subscribed_at = NULL" not in body, start
    assert "DELETE FROM playlist" not in body, start
    assert "id NOT IN" not in body, start
    assert "try entity.save(db)" in body, start

start=src.index("func unmarkStaleLikedSongs(")
end=src.index("func deletePlaylistRows(",start)
body=src[start:end]
assert "db.write" not in body
assert "liked = 0" not in body

# Explicit user-initiated delete still works; only external-absence removals
# are prohibited.
assert 'DELETE FROM playlist WHERE id = ?' in src
assert 'DELETE FROM playlist_song_map WHERE playlist_id = ?' in src
print("Legacy remote-sync additive-only safety checks passed")
PY
