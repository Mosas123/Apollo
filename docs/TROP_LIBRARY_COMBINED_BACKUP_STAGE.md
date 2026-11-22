# Trop combined metadata archive — experimental stage

**Status:** internal-only schema/service on draft PR #80. No new Settings
control, no restore button and no shipped restoration. The verified iPhone
export/inspect UI continues to use the existing V2 JSON format.

## Why this exists

Two independent drafts existed:
- PR #67: metadata-only legacy `trop-library-metadata` v1 (songs,
  bookmarked artists/albums, playlists, episodes and podcasts).
- PR #80: metadata-only `trop-library-v2-metadata` v2 (Trop UUID items,
  safe provider aliases, ordered playlist entries/duplicates, radio, imported
  membership ledger and links).

Neither alone is a complete library rescue archive. The combined prototype
allows a consistent capture of both schemas **in one GRDB read transaction**.
It does not silently change the previous formats or move existing data.

## Transport contract

- Format: `trop-library-combined-metadata`, version `2` (distinct from
  the earlier standalone version numbers). This new internal version adds
  provenance; version 1 was never released to users.
- JSON with sorted keys, dates in milliseconds and SHA-256 over the canonical
  payload. This is **corruption detection, not encryption/authentication**.
- Payload consists of full `legacy` and `libraryV2` snapshot objects **plus**
  `legacyMemberships` containing each original positive `playlist_song_map.id`,
  playlist ID, song ID and position. Both library sections pass their existing
  allowlist/record/reference/privacy validators; the new membership map must
  correspond **exactly** to every legacy playlist entry, with no missing,
  duplicated or forged source row IDs. The independent legacy `.tropbackup` v1
  archive stays unchanged.
- 40 MiB outer limit; the component 16 MiB legacy and 24 MiB V2 limits also
  apply. No downloads, audio files, playback URLs, addon manifests, cookies,
  bearer tokens, login credentials, app settings or user-private logs.
- The six V2 tables and legacy metadata queries share a **single database
  read**. An archive assembled from sequential asynchronous reads would risk
  mixing incompatible playlist/edit states.
- Output can include provider-scoped catalog IDs, which may be personal
  metadata. Handle it as a private unencrypted document.

## Restore is deliberately not available

The V2 legacy-import ledger stores integer `playlist_song_map.id` values
specific to **one database**. The combined v2 envelope now captures the
original row-ID-to-playlist/song/position mapping in the **same** GRDB read,
while PR #67 standalone legacy backup v1 still lacks those IDs.

**This fixes the missing-source-membership metadata, NOT the safety of
cross-device restoration.** Imported-entry ledger tombstones may reference
memberships already deleted from legacy. They are retained and counted as
`ledgerEntriesWithMissingMembership` by the preview. Never replay them blindly.

### Read-only destination remapping prototype

`TropLibraryCombinedRestorePlanner` now validates an explicit
**source membership → SQLite-assigned destination ID** mapping. It verifies
the exact playlist/song/position identity, checks completeness, positive
destination IDs, unique sources and unique destination IDs, then builds a
**new V2 import ledger in memory** using only mapped destination IDs.

It **fails closed** when a deleted source membership is still mentioned by
the import ledger (orphan tombstone), because there is no safe destination
identity for it yet. It also refuses missing, foreign and mismatched rows.
The planner does **not** read/write the production DB, allocate IDs,
create a new source origin, delete a tombstone or enable restore UI.

The GRDB fixture separately tests fresh SQLite `AUTOINCREMENT`-assigned IDs
that differ from the original source ID, verifies the remapped ledger and
proves an orphan rejection rolls back a sandbox transaction. This test is
not a complete legacy+V2 restore and is not on-device QA.

Remaining design: an origin-scoped, stable identity for deleted membership
tombstones, source/destination provenance and idempotent/repeat restore.
Until that is solved, a combined backup with orphan imports is explicitly
**blocked from full restoration**; dropping these tombstones silently is
not acceptable.

Before any public Restore action:

1. Design a stable origin identity plus *destination remapping* and tombstone
   strategy with explicit foreign-device behavior. Refuse ambiguous mappings, rather than
   silently treating foreign IDs as local rows.
2. Preserve legitimate duplicate playlist positions (V2) while respecting
   legacy uniqueness rules; never de-duplicate across independent namespaces.
3. Implement one all-or-nothing **legacy+V2** GRDB restore into a verified
   empty *test* target. Forbid overwrites on an installed library and prove
   rollback after injected errors.
4. Verify data from legacy podcast/episode/album/artist relationships and
   ensure no private manifests, login tokens or signed stream URLs leak.
5. Add repeat restore, corrupted archive, large-file, interrupted operation,
   power-loss simulation where feasible and on-device QA before enabling UI.
6. Keep an explicit route from source/provider IDs toward Trop-owned
   identities and alternatives when YouTube is disabled; backup **does not**
   guarantee playable streams.

PR #67 remains an independent draft. The two legacy snapshot source files
were staged into #80 for cross-format CI; resolve their ownership and merge
history before final integration. Do **not** merge the drafts blindly.

## Validation

`scripts/test-trop-library-v2-recovery.sh` compiles all three archive
formats with Swift 6 strict concurrency, checks tampering/version rejection,
and refuses addon-private aliases. `test-trop-library-v2-grdb-integration.sh`
builds the *actual production store files* against pinned GRDB 7.12.0,
asserting a combined export uses exactly one database read, preserves
both legacy and V2 rows, captures actual SQLite-assigned membership IDs and
rejects orphan-ledger remapping within a rolled-back sandbox transaction.
CI is not an on-device restore test; check the HEAD workflow result before
calling the new fixture passed.
