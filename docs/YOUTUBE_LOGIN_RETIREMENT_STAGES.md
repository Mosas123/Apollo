# Retire YouTube Music login: user-owned Trop library

**Status: staged rollout, not yet iCloud-enabled.**

## Product decision

A Trop user must be able to save their own songs, albums, followed artists,
playlists, podcasts and episode progress without signing into YouTube Music.
The Trop-owned library is persisted locally in GRDB and later reconciled via
the user's private iCloud CloudKit database. Only library **metadata** is
synced; **no audio files or downloads, cookies, credentials, streaming URLs
or device paths** belong in iCloud.

Do not remove the old login and its linked import mechanism before backing
up/migrating the currently saved local and legacy account library. Removing
the login UI without migrating data is not removing the underlying dependency.

## Stage 1: first safe behavior change (this draft)

- Creating a **new playlist** always inserts a new local `PlaylistEntity`
  with a Trop-generated UUID, `browseId=nil` and no YouTube Music request.
- Remove the old "Sync playlist" toggle from the new-playlist dialog.
- Explicit user-facing text says the playlist is only **on this device**
  and that **iCloud sync is not implemented yet**.
- Existing YouTube-linked playlists, their membership and account sessions
  are untouched and still accessible as before.
- No change to likes, saved albums/artists, podcast subscription behavior,
  Search, ApoloEngine, FFmpeg or provider routing.

## Next steps — each a separate tested PR

1. **Non-destructive legacy snapshot / import preview**: export or read
   existing saved songs, favorites, album/artist bookmarks, podcasts,
   and playlists from GRDB; optional one-time user-authorized Google library
   import while old credentials remain usable. Require preview/diff, preserve
   alias records, never treat empty Google account as a deletion.
2. **Canonical Trop identity + transactional GRDB migration**: per-recording,
   release, artist, playlist, podcast and episode UUIDs; reversible aliases
   from YouTube IDs, MBIDs/ISRC/provider IDs; preserve all saved rows,
   playlist ordering, and repeated playlist occurrences (legacy UNIQUE key
   currently prevents duplicates).
3. **Local-first likes and bookmarks**: save/unsave routes operate only on
   Trop IDs and local GRDB; refactor SyncBridge so old YTM pull cannot
   overwrite user-owned changes. Verify old and new saved lists.
4. **CKSyncEngine private-zone metadata sync**: durable local outbox,
   dedup/idempotency, conflict-aware merges, offline support and two-device
   verification. Do **not** promise iCloud restoration until real QA passes.
5. **Retire the general YouTube sign-in**: remove account prompts, YTM
   favorites/history mutations and automatic library sync only after
   preserving existing data; optionally offer a **separate, explicit**
   one-time import flow with consent, then delete session credentials on
   the user's request. Do not wipe old cookies during a migration.
6. **Import from other platforms**: existing
   `Trop/Core/LibrarySync/PortableLibraryCSVImporter.swift` supports
   read-only Soundiiz / Spotify Exportify-style and generic CSVs;
   `LibraryImportPlanner` previews duplicates and ambiguities.
   These are *not yet a UI or a database import*. Add a Files picker,
   explicit preview, atomic commit/rollback, podcast OPML, and later
   documented service exports (Spotify, Apple Music, Google Takeout).
   Prioritize offline file imports over account OAuth connections.
7. **Separate streaming source provider policy**: only request audio from
   a provider with authorized transport/terms. YouTube API Services
   restrict audio-video separation and certain background uses; removing
   library login does not confer audio-only playback rights.

## Tests for this stage

`bash scripts/test-trop-owned-playlist-creation.sh` checks the real
creation dialog contains the local GRDB route and no YouTube request.
The iOS Nightly build and on-device QA must still confirm that:
- A new playlist can be created while logged out of YouTube.
- The playlist survives app restart, without logging in.
- Existing playlists stay visible, editable and ordered.
- Creating a playlist sends no `createPlaylist` mutation to YouTube.
- No misleading "already synced to iCloud" claim appears.
- This experimental build is **not** used as the sole backup of the library.

Do not merge to main before the test and on-device QA are reviewed.
