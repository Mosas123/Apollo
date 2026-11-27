# Apollo — Import Replay & Music Sync Routing (Phase 8)

This phase prepares protections for **repeat imports** and **outbound changes**
when users have connected YouTube Music and optional trackers. It is a
foundation ONLY. There are no remote API calls, background sync, database
writes, token usage or user-facing settings in this PR.

## Existing behaviour verified

- Apollo currently uses YouTube Music \`MutationService\` for likes/unlikes,
  add/remove library items, playlist edits, artist and podcast subscriptions.
- Apollo already has Last.fm scrobbling and optional love/unlove support.
- Phase 6 plans canonical library identity mapping; Phase 7 adds a read-only
  CSV parser. Neither is yet a fully transactional import or history merger.

## Replay-safe import design

- After a successful, **transactional** import (future PR), persist an
  \`MusicImportReceipt\`: destination Apollo profile ID, import mode, SHA-256
  of source file and an optional confirmed stable source identifier.
- Same content + same source + same profile + same mode => already applied.
- An updated export from the same source => present a delta preview, never
  create a second automatic copy and never infer deletion from missing rows.
- Same content belonging to a *different* playlist/source => do not blindly
  collapse two legitimate playlists.
- Different Apollo profiles always remain separate.
- Within each import, Phase 6 source-ID and validated-ISRC matching will
  link identical recordings; metadata-only ambiguous matches need review.
- Preserve duplicate track occurrences **within a playlist** when
  intentional, while keeping canonical library tracks deduplicated.
- Never silently merge releases, artists, podcasts or episodes by name.
- File receipts and the history of applied source links must be committed
  atomically with imported rows; this PR does not implement that transaction.

## Outbound synchronization design

- **Only user-initiated changes** may produce outbound actions. Remote
  refreshes, file imports and restored backups are always local-only.
  In particular, importing a year's history NEVER re-scrobbles it.
- Connected accounts are explicitly scoped to one Apollo profile, with
  separately enabled favorites/library/playlists/listens categories.
- YouTube Music: eligible likes, library saves, artist subscriptions,
  podcast subscriptions and owned playlist edits, **only after**
  mapping the track/podcast and verifying access to the active account.
  No guessing YouTube IDs from Spotify/Audius/Qobuz titles.
- Last.fm: loved/unloved tracks and eligible listens only. It does not
  support syncing a full podcast library or playlists as such.
- ListenBrainz: listens and recording love feedback when a verified
  MusicBrainz recording MBID exists. This is a *future* connector; Apollo
  does not currently have it built in.
- Each local action gets a stable event ID and each destination gets its
  own idempotency key. Duplicate delivery plans do not multiply actions.
- Pending state changes (like -> unlike) coalesce to the newest intent.
  Once in flight, a request cannot be safely cancelled; later changes
  must be serialized and reconciled.
- Playlist insertions and legitimate repeated listens remain distinct.
- Unknown response after a network timeout is marked \`uncertain\` and
  must be reconciled before replay. External APIs may not support
  exactly-once semantics.

## Required next steps before this can be enabled

1. Persistent per-profile import receipts and source links in GRDB,
   with transactional commit, rollback and migration tests.
2. Durable **outbox** persisted atomically with local edits; order writes
   per item/account. Store no secrets in event payloads.
3. On-device settings to select destination services and action types.
   Imports must have their own optional, explicit **Export imported
   favorites** flow, never silently upload mass imported data.
4. Live adapters behind the existing YouTube mutations and Last.fm
   integration; implement ListenBrainz only when opted in.
5. Offline queue, rate limits, session-change guards, error UI, retry/
   reconciliation (especially for scrobbles) and end-to-end iOS tests.
6. Restrict changes to permitted provider operations and handle token
   expiration, account changes and cases with no matching remote item.

Tests: \`bash scripts/test-music-sync.sh\` (Swift 6 / Foundation only).
Fixture IDs are fictional. This PR is intentionally not active runtime
sync and should remain **Draft** until owner review.

References:
- https://www.last.fm/api/scrobbling
- https://listenbrainz.readthedocs.io/en/latest/users/api/core.html
- https://listenbrainz.readthedocs.io/en/latest/users/api/recordings.html
