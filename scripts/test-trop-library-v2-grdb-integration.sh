#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

package="$temp_dir/package"
mkdir -p "$package/Sources/V2RecoveryGRDBFixture"

cp tests/LibrarySync/V2RecoveryGRDB/Package.swift "$package/Package.swift"
cp tests/LibrarySync/V2RecoveryGRDB/RecoveryFixture.swift \
    "$package/Sources/V2RecoveryGRDBFixture/RecoveryFixture.swift"
cp Trop/Core/LibrarySync/TropLibraryV2IdentityPolicy.swift \
    "$package/Sources/V2RecoveryGRDBFixture/TropLibraryV2IdentityPolicy.swift"
cp Trop/Core/LibrarySync/TropLibraryV2RecoveryArchive.swift \
    "$package/Sources/V2RecoveryGRDBFixture/TropLibraryV2RecoveryArchive.swift"
cp Trop/Core/LibrarySync/TropLibraryV2RecoveryStore.swift \
    "$package/Sources/V2RecoveryGRDBFixture/TropLibraryV2RecoveryStore.swift"

# Compile the exact same legacy+V2 combined-store code as the application.
for name in TropLibraryBackupArchive TropLibraryBackupService \
            TropLibraryCombinedBackupArchive TropLibraryCombinedBackupService \
            TropLibraryCombinedRestorePlanner; do
    cp "Trop/Core/LibrarySync/$name.swift" \
        "$package/Sources/V2RecoveryGRDBFixture/$name.swift"
done

# Extract the real v10, v11 and v12 SQL statements rather than retyping or
# approximating the migration schema in a hand-maintained test fixture.
python3 - "$package/v2.sql" <<'PY'
import re
import sys
from pathlib import Path

text = Path("Trop/Database/DatabaseMigrations.swift").read_text()
statements = []
for current, following in [("v10", "v11"), ("v11", "v12"), ("v12", "\n}")]:
    section = text.split("static let " + current + ":", 1)[1]
    if following == "\n}":
        section = section.split("\n}", 1)[0]
    else:
        section = section.split("static let " + following + ":", 1)[0]
    statements += re.findall(r'try db\.execute\(sql: """(.*?)"""\)', section, re.S)
assert len(statements) == 10, "Unexpected Library V2 migration DDL"
Path(sys.argv[1]).write_text("\n--V2DDL--\n".join(statements))
PY

# Package is isolated, so it cannot mutate the repo's own Package.resolved.
# It compiles the production Archive and Store *unchanged* against the same
# GRDB version as the iOS project, then exercises real transaction semantics.
swift run --package-path "$package" \
    --configuration debug V2RecoveryGRDBFixture "$package/v2.sql"
