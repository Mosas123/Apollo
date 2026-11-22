# Portable Trop library backup — initial implementation

**Status:** Experimental, metadata-only **export + integrity preview** on PR #67.
This is **not yet a safe restoration path**. Do not remove YouTube login or
reinstall an IPA relying solely on this file until atomic restore is proven.

## UX

Settings → Library Backup → **Export .tropbackup** → choose an iOS Files
destination (On My iPhone, iCloud Drive when enabled, or a supported third-party
File Provider such as Google Drive, Dropbox or OneDrive).

Settings → Library Backup → **Verify backup from Files** → read-only SHA-256
verification and counts. No database writes. If iCloud Drive is disabled, the
local and enabled third-party locations can still work, subject to each
provider's Files integration and the user's installed apps.

Exporting is manual. Files is not a background sync protocol and does not
require CloudKit entitlements, Google OAuth or per-provider SDKs.

## Format

- Custom UTI `org.apoloengine.tropbackup` / extension `.tropbackup`.
- JSON `format=trop-library-metadata`, `schemaVersion=1`.
- `createdAt`, canonical `library` payload and its SHA-256 digest.
- Sorted-key JSON and millisecond Date encoding for repeatable checksums.
- 16 MiB maximum serialized size and 125,000 maximum metadata records.
- Future schemas fail closed. Damaged files fail their checksum check.
- Checksum detects accidental corruption; it is **not cryptographic
  authentication, not an encryption scheme, and not proof of provenance**.

## Included (explicit allowlist)

- Liked tracks, in-library tracks and tracks referenced by playlists:
  legacy ID, title, artist/album name, duration, liked flag, library date,
  basic episode flag, creation date.
- Bookmarked albums and followed artists with saved dates.
- All legacy playlist rows (including temporarily unbookmarked ones) and
  **all playlist membership rows**, with original order and unresolved IDs
  kept for later review. A future membership UUID migration must preserve
  repeated song occurrences, unlike the existing SQLite unique constraint.
- Subscribed podcasts and saved episodes with their basic metadata.

## Excluded

- **No music/audio files, downloaded track paths or formats.**
- No cookies, sign-in data, OAuth tokens, YouTube mutation tokens or
  remote playback tracking data.
- No stream URLs, cached or signed URLs, artwork URLs or local device paths.
- No arbitrary events, playback history or play-count table in v1.
- No automatic uploads or private CloudKit connection.

Portable metadata alone does not guarantee a playback source on another
device: the new device must resolve the recording with a permitted provider.

## GRDB safety

The export uses one `DatabaseService.shared.read` closure and select
statements that name only approved columns. It does not mutate the database.
The UI verifies the in-memory archive before showing the iOS Files exporter.
Imported files are **validated only**; there is intentionally no apply button.

## Remaining release gates

1. Device QA: verify the archive counts match Library Migration preview
   (including all playlist entries) and can be exported with iCloud Drive OFF.
2. File-provider QA on a second Files destination, plus corrupt/truncated file
   verification; confirm the library is unchanged.
3. Design transactional restore staging, identity/alias reconciliation,
   atomic commit and rollback, and anti-overwrite/anti-delete policy.
4. Add optional password encryption before advising backups to untrusted
   destinations, and present a clear warning until encryption exists.
5. Only then migrate GRDB identity and retire YouTube library coupling.
6. Existing new-playlist offline issue stays in the final acceptance list.

The existing user may be limited to an iPhone and remote GitHub Actions;
no Mac/Xcode local action is required for device QA.

CI: `bash scripts/test-trop-portable-library-backup.sh` on macOS.
