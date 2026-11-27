# Apollo Library Import & Merge — Stage 1

## Goal

One user-owned, opt-in library that can *reference* albums, artists,
songs, playlists, podcasts and episodes originating in multiple services,
without deleting local edits, duplicating content or confusing accounts.
This is **not** a way to copy third-party audio binaries.

## What Apollo already does

- Authenticated YouTube Music integration uses InnerTube cookies.
- SyncBridge / LibrarySyncService cover artists, saved albums, liked
  playlists, subscribed podcasts and liked songs.
- The current incremental sync runs when stale (>30 minutes), and Library
  can force sync.
- It does not yet offer an account-scoped merge planner or a unified source
  provenance registry.
- History currently has separate Local and Remote views, not one imported
  replay-safe event ledger.
- Current sync paths mirror remote state in certain places, including
  unmarking removed likes/subscriptions and removing disappeared
  auto-synced playlists. Therefore, a new feature must not call existing
  destructive sweeps on incomplete or wrong-account results.

## This PR (standalone, non-destructive foundation)

The LibraryImportPlanner calculates a read-only preview given:
- incoming metadata-only library items,
- existing canonical entries and their provider/account references,
- an explicit currently authorized account ID,
- user-selected categories to import.

It returns:
- new canonical items to create,
- new source links for already-known ISRC tracks,
- already present items,
- duplicate records within this import,
- items excluded by category choice,
- ambiguous references needing user review.

It never modifies the database. A future transactional commit path must
revalidate that the signed-in account is still the same account immediately
before committing. No source is treated as authoritative for deleting
unrelated local state or another provider's data.

### Deduplication

1. Exact provider + account + remote ID → same source item; no duplicate.
2. Validated ISRC on tracks only → link to one canonical recording.
3. Conflicting multiple ISRC candidates → review, never guess.
4. Same song/playlist/podcast title alone → NOT an identity match.
5. Imported items from the same batch with a verified matching ISRC
   become one new canonical track with multiple provenance references.
6. Different podcast episodes, multiple play events and user playlist
   entries are NOT deduplicated merely for having matching titles.

Per-source provenance is preserved. Matching does not replace local names,
likes, offline files, podcast progress, playlist ordering, or metadata
edited inside Apollo.

### Account safety

- Data from a different account fails the entire preview.
- No deletion is inferred from an empty import, failed request, unavailable
  category or an account that has not loaded.
- Account IDs should be opaque stable identifiers, not email addresses
  or cookies, and should be stored in a secure app-controlled data model.
- No data is uploaded or synchronized to third-party services by this
  planner, and imported history is never automatically scrobbled.

## Future work, in separate PRs

1. Approval UI + preview counts and account/source controls.
2. Database migration: canonical identities, ownership/provenance,
   source-scoped playlists and per-account sync checkpoints; atomic
   commit and rollback. Migrate existing local items without resetting
   user metadata. Include a safe account-switch strategy.
3. Google connection integration: source adapters for officially
   available data, consent-aware refresh and initial full fetch with
   pagination. Existing InnerTube behavior must be reviewed against
   Google's terms; credentials must remain private.
4. Optional **user-exported** Google Takeout JSON or Google Data Portability
   imports to cover information the normal YouTube Data API cannot return.
5. Unified history with true per-listen deduplication (provider event ID,
   timestamps and track identity) and podcast position reconciler.

## Google capabilities & limits

The official YouTube Data API supports authorized playlists, playlist
items and subscriptions; however, watch history is not retrievable via
that API. Google's Data Portability API has a YouTube Music library scope
and requires app review, appropriate user consent and regional eligibility.
Do not promise automatic access to every detail such as podcast progress,
all plays or private uploads.

YouTube API client policies govern metadata retention and prohibit
unapproved copies of audiovisual content; they also constrain mixing
YouTube API data into unrelated cross-service products. Get a compliance
review before shipping any cross-service aggregation. The user's consent
alone does not override the platform's API restrictions.

Links:
- https://developers.google.com/youtube/data/reference/rest/v3/playlistItems/list
- https://developers.google.com/data-portability/user-guide/introduction
- https://developers.google.com/data-portability/user-guide/scopes
- https://developers.google.com/youtube/terms/developer-policies

## Validation

Run: bash scripts/test-library-import.sh (Swift 6, Foundation only).
All test names and provider IDs are fictional. No personal accounts or
live APIs are used. iOS build and existing SyncBridge regressions must be
checked before wiring this into user data.

**Draft only. Do not merge until reviewed and tested.**
