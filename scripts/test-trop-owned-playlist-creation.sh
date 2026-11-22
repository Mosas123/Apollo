#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
file="Trop/Library/LibraryView.swift"

# Test against the actual create-playlist UI implementation. Existing
# playlist sync/legacy import is intentionally not changed by this stage.
python3 - <<'PY'
from pathlib import Path
source=Path("Trop/Library/LibraryView.swift").read_text()
start=source.index("struct CreatePlaylistDialog: View {")
end=source.index("// MARK: - AutoPlaylist Info", start)
dialog=source[start:end]
checks={
    "local playlist identity": "let id = UUID().uuidString" in dialog,
    "no remote browse link": "browseId: nil" in dialog,
    "local GRDB creation": "DatabaseService.shared.insert(entity)" in dialog,
    "no login necessary": "CookieStore" not in dialog and "isLoggedIn" not in dialog,
    "no YouTube mutation": "SyncBridge.mutations.createPlaylist" not in dialog,
    "no YouTube toggle": "syncWithYouTube" not in dialog,
    "no claim of working CloudKit": "iCloud sync will be added later." in dialog
}
for key, ok in checks.items():
    print(("PASS" if ok else "FAIL"), key)
assert all(checks.values()), "New playlist must remain Trop-local and account-independent"
PY
