# Trop private iCloud library — metadata-only contract (draft)

## User-owned data boundary

Sync through the user's **private CloudKit database**:
- Saved songs/favorites, albums, artists
- User playlists and the order of songs (including duplicates)
- Followed podcasts, saved episodes and optionally playback progress

**Never sync downloaded FLAC/MP3/M4A/audio bytes, device file paths, signed streaming URLs, cookies, credentials, transient queue or audio caches.**

A device's **local GRDB SQLite** database remains the immediate source of truth. The app continues to work offline and without an iCloud account. CloudKit is an asynchronous replica, not a prerequisite for playback.

## Stage 1 — implemented as draft contracts only

- TropCloudItemID: a stable scoped Trop UUID for each recording, album, artist, playlist, podcast or episode. No YouTube ID is authoritative.
- TropCloudSourceAlias: separately scoped reversible aliases to catalogue or legacy provider IDs, rejecting URLs, query tokens and control characters. A legacy YouTube alias never authorizes remote playlist or library writes.
- TropCloudLibraryRecord: metadata-only item details, an optional deletion tombstone, and episode progress only on episode records.
- TropCloudPlaylistEntry: its own membership UUID, playlist/recording IDs, ordinal position, modification time and tombstone. Repeated tracks can have separate membership IDs.
- TropCloudLibrarySyncPolicy: only explicit local user actions may enqueue cloud exports; incoming provider refreshes, imported files and remote cloud changes must not echo mutations. Conflicting deletions are not blindly applied.
- Mock-only Swift 6 tests and CI; no CloudKit entitlement, CKSyncEngine or real sync activated yet.

## Next integration stage — CKSyncEngine and GRDB

1. Add the iCloud capability / private CloudKit container and implement CKSyncEngine's documented state persistence. Do not create a live environment until signing and entitlements are verified.
2. Integrate a durable transactional GRDB outbox. Track upload acknowledgements, server changes, revision and schema, and retries without duplicating saves.
3. Write a reversible alias migration for current SongEntity.id, PlaylistSongMap.songId, liked flags, saved albums/artists, podcasts, playlist order and existing local edits. Do not rewrite or delete YouTube-based rows in this PR.
4. Resolve conflicts with explicit per-record causal state; timestamps from different devices alone do not ensure a safe ordering. Tombstones should not delete offline device data without reconciliation.
5. Require end-to-end iPhone/iPad QA: new device restoring library, offline edits, concurrent playlist reorder, delete-and-restore, account change, storage full, sign-out, reinstall, quota and rollback.
6. After all gates, disable reliance on YouTube Music as library/catalogue authority. YouTube source lookups, if authorized, are a separate playback provider; no YouTube library mutations or listen tracking as a side effect of saving to Trop.

## Explicit non-goals / guardrails

- No iCloud music locker, audio file copying or downloading on another device automatically.
- No storage of account tokens, video URLs or expiry-sensitive provider URLs.
- No silent conversion of a music video into a studio recording; aliases are not proof of equivalence.
- No assertion that iCloud improves a first-time audio lookup. Local library indexes speed only known-item retrieval.
- No merge to main until migration, licensing, Apple entitlements and device tests are reviewed.

This stage stacks on Trop PR #56 (read-only MusicBrainz catalog). Audio EOF issue remains independent: ApoloEngine issue #26 / PR #27.

## Test

Run: bash scripts/test-trop-cloud-library-contract.sh

Mock-only checks: Codable metadata, stable scoped IDs, podcasts, episodes, playlist membership and order, tombstones, external-ID URL rejection and anti-echo policy. These tests **do not** demonstrate working CloudKit sync.
