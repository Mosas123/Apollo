# Trop Library V2 — clean ownership without destructive reset

**Status: experimental additive foundation. NOT the active library UI.**

## Product choice

New Trop installations will eventually start with an **empty Trop-owned**
library. A YouTube Music account, old YouTube keys, or legacy sync must
never be prerequisites to create favorites and playlists.

Existing installations keep every legacy song, like, album, podcast,
download and playlist untouched. A **clean start is a new namespace**, not
a mass deletion or dropping existing tables. An existing user can later
choose to keep the old data isolated, migrate it, or reset it after a verified
backup and explicit confirmation.

## Stage 0 — this PR

- Database migration v10 creates three empty trop_v2_* tables alongside
  existing GRDB tables, with no copying or legacy mutation.
- trop_v2_item: independent UUID, kind, title, optional artist/author,
  duration, saved/liked timestamps. No compulsory account identity.
- trop_v2_playlist_entry: membership UUID, ordered position, references
  to independent playlists/recordings. Repeated songs are allowed.
- trop_v2_source_alias: optional provider+scope+kind+external-ID link to
  a Trop item. It is provenance, **not** the item's authoritative ID,
  a sync instruction, an authenticated source or playback permission.
- TropLibraryV2Store provides local record creation, likes, playlist
  creation and duplicate-preserving append, provider alias links and reads.
- No YouTube API, login UI, CloudKit entitlement or background service is
  required for these new store functions.
- Pure Swift 6 alias/UUID tests and SQLite v10 smoke with a legacy fixture.
  iOS compilation is checked separately through Nightly.

## Non-goals and invariants

- No migration of existing YouTube data, no automatic removal of old data.
- No replacement of LikeStore, SyncBridge, search, album/artist pages,
  podcast pages, history or current playlist UX **in this PR**. They still
  use legacy paths until we move them explicitly.
- No live CloudKit, Google Drive synchronization, playback routing changes
  or audio re-downloads.
- No exports of cookies, credentials, stream URLs or signed media.
- Source aliases are not evidence that two recordings are identical.
- A new table does not create an independent catalogue or grant provider
  transport rights.
- Existing backup PR #67 exports legacy metadata safely; its schema is **not
  automatically the V2 export format**. V2 backup/restore needs an adapter.

## Next isolated steps

1. Connect the new Library UI and all **user save actions** to the V2 store.
   A fresh install displays an empty new library; a legacy user sees an
   explicit non-destructive choice. The old account does not sync V2.
2. Allow creation and reordering of V2 playlists without login, including
   multiple instances of a recording in one playlist; phone QA offline.
3. Add a transactional import preview from selected platform exports or
   manual files. Explicit item-level consent, alias verification and rollback.
4. Export and restore V2 data in a versioned backup; verify the restore using
   a spare profile/fixture, not the user's only saved copy.
5. Add optional synchronization with real signing/entitlement checks. Offline
   V2 must remain usable without iCloud or another cloud provider.
6. Retire old YTM account prompts, library sync, mutations and history
   tracking from the active UI only after V2 flows are proven.
7. Keep existing legacy DB available for opt-in import or explicit later
   deletion. Never erase it as a migration side effect.

Do not merge the experiment into main without a deliberate release/data
safety review. The user needs no new test IPA just to validate this schema.
