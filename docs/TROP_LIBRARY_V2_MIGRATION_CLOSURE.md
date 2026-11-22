# Library V2 migration — closure gates (22 November 2026)

**Status: IN PROGRESS, draft branch PR #79. Do not enable import for users or merge to main yet.**
This checklist is intentionally non-destructive. CI success is not evidence of a
restorable backup, complete playback experience or safe migration on an iPhone.

## Stage 1: transaction-safe importer (code staged in PR #79)

- [x] Additive GRDB v12 schema with per-legacy-membership idempotency ledger
  and safe references for album → playlist and episode → podcast metadata.
- [x] Import candidate records from a single persistent legacy snapshot:
  liked/in-library/playlist songs, bookmarked playlists, albums, artists,
  followed podcasts, saved episodes, and saved playlist membership order.
- [x] Trop-owned UUIDs, provider-scoped aliases and no YouTube login.
- [x] Reruns reuse source aliases, do not rename/unlike existing V2 records,
  do not re-create memberships removed by the user.
- [x] Abort and rollback on source alias conflicts, malformed metadata,
  orphaned saved playlist memberships, broken lineage or temporary DB fallback.
- [x] No legacy table changes, audio bytes, credentials, cookies,
  signed streaming URLs, raw paths or automatic CloudKit writes.
- [ ] Verify Swift importer itself with a dedicated GRDB/in-memory integration
  fixture (not just schema-level SQLite test and Nightly compilation).
- [ ] Prove large-library performance, memory and cancellation with fixture data.

## Stage 2: complete local V2 user experience (HARD GATE)

- [ ] Tap saved song or playlist track to play its resolved alias, preserving
  queue context and correct metadata even for non-YouTube add-ons.
- [ ] Playlist create/rename/delete, entry remove/reorder, duplicate occurrence
  semantics and undo without deleting a saved recording unexpectedly.
- [ ] Album/artist/podcast/episode browse, artist attribution and artwork,
  with offline placeholders rather than fake playable media.
- [ ] Favorites, source aliases and local downloaded audio consistently
  survive app relaunch, no-network and YouTube-account logout.

## Stage 3: user-owned backup and restore (HARD GATE)

- [ ] Integrate or adapt PR #67's legacy-only metadata archive into a **V2-aware
  versioned backup** that also includes existing V2 rows and import lineage.
- [ ] Files-based export and **verified transactional RESTORE**, not just SHA-256
  preview. Checksum is corruption detection, NOT encryption/authentication.
- [ ] Preserve playlist order, repeats, identity aliases, deletion tombstones,
  radio favorites, episode/album relations and conflict strategies.
- [ ] Restore in isolated fixtures first; reject wrong version/checksum, missing
  references, oversized/corrupt archives and ambiguous aliases **before commit**.
- [ ] Show preview + explicit user confirmation and a recovery path.
  No import button before this stage passes; no loss of preexisting V2 data.

## Stage 4: user-confirmed migration

- [ ] Dry-run difference counts, blocked rows and alias conflicts with NO writes.
- [ ] Require verified backup proof and explicit opt-in, then call the importer.
- [ ] Verify source/target counts, entry order and recording identity, rerun
  idempotence, restart during import, rollback, and reversibility by toggling
  legacy/V2 without deleting the old database.
- [ ] Agree how to handle unbookmarked legacy playlists and unresolved members
  without silently dropping them or promoting deleted remote metadata.

## Stage 5: optional iCloud metadata sync

- [ ] Use PR #57 as a contract only, not as functional CloudKit.
- [ ] Verify actual signing/entitlements for AltStore/SideStore/Feather; if not
  available, Files backup + local GRDB MUST still work.
- [ ] Test private metadata-only sync, conflicts, tombstones, offline edits,
  device-to-device recovery and account changes. Never upload audio/credentials.

## Stage 6: single release candidate

- [ ] One integrated IPA from GitHub Actions, iPhone QA on migrated and fresh
  profiles, including rescue backup round-trip and privacy review.
- [ ] Confirm all required CI; record inherited failures separately and fix
  migration-related ones instead of misreporting full green.
- [ ] Only then decide stacked PR merges into main; keep other future features
  (Hi-Res/Dolby settings, DJ, general visual redesign) out of the critical path.

**Operational principle:** New unrelated non-critical bugs go to the backlog,
not to another IPA. Data loss, privacy, backup corruption or a true migration
blocker take immediate priority. User QA takes place on an iPhone, not Xcode on
a local Mac.
