# Trop independent music identity — phase 1 (draft)

## Why

The legacy discovery and queue model stores `SongItem.videoId` even for
music selections. YouTube/InnerTube can surface OMV/UGC video soundtracks
where the user intended an official album recording. Source matching
policies reduce this, but they cannot create an independent recording
identity while `videoId` remains the database key.

**Decision:** separate the music catalogue from the provider used to play
the audio. A recording is not a stream URL and not a video ID.

## Phase 1 implemented by this draft

- Add a **read-only**, explicit MusicBrainz entity client for **recordings,
  artists and release groups**: `MusicBrainzIdentityCatalog`.
- Each candidate carries an entity-qualified ID:
  `musicbrainz:recording:<MBID>`, `musicbrainz:artist:<MBID>`,
  `musicbrainz:release-group:<MBID>`.
  A release group is not an edition (release) and not a recording.
- Filter explicitly marked video recordings; preserve mixed artist-credit
  join phrases; skip invalid UUIDs and duplicate hits. Durations and optional
  ISRCs are *hints*, not sufficient to prove a particular master.
- Never advertise these catalogue candidates as playable or convert them
  into `SongItem.videoId`. No stream API, playback routing, library writes,
  downloads, automatic substitutions, artwork downloads or user-facing UI.
- Search endpoints use HTTPS JSON, a meaningful User-Agent, URLComponents,
  a process-wide actor limiting requests to **at most one per second**,
  cancellation, bounded result counts, 12-second timeout and 2 MiB JSON
  decoding cap. Transport can be injected for network-free tests. An HTTP
  429 remains an error rather than silently falling back to a video.
- None of the existing YouTube/music-addon, ApoloEngine, ApoloFFmpeg, queue,
  GRDB persistence or user-library behavior changes in this phase.

## Legal / operational gates

The underlying MusicBrainz **core data** is available under CC0, but that
does **not** automatically grant unrestricted use of the MusicBrainz-hosted
web API in a commercial product. Obtain appropriate API/commercial access,
self-host, or arrange an authorized licensed service before enabling
production traffic. Do not deploy a client-side search feature to production
solely because the fake-transport tests pass.

Public references:
- https://musicbrainz.org/doc/MusicBrainz_API
- https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting
- https://musicbrainz.org/doc/MusicBrainz_API/FAQ
- https://musicbrainz.org/doc/MusicBrainz_API/Search

Album art is a **separate asset/rights problem**. Cover Art Archive may
be evaluated as a candidate; do not assume album artwork rights from CC0
music metadata. Do not use Spotify/iTunes artwork contrary to their terms.

## Acceptance roadmap before any YouTube catalogue retirement

1. **Identity model:** introduce a Trop-owned, stable `RecordingID`, a
   distinct `ReleaseID` and `MusicVideoID`. Map each to external MBIDs,
   ISRCs (when verified), provider-specific track IDs and release editions.
   An MBID is not guaranteed to exist for every requested song or release.
2. **Selection:** match recordings by strict title, principal artist,
   release/edition and duration, with confidence and explicit ambiguity
   states. Never silently pick a remix, cover, live version or video mix.
   No result -> “unavailable” or manually selected fallback; not random ATV.
3. **Preserve user data:** migrate old `SongEntity.id`,
   `PlaylistSongMap.songId`, user likes, play history, saved albums,
   downloads, Next/Previous queues and cache keys through **reversible**
   alias tables. No destructive database migration or ID rewrites on this PR.
4. **Playback decoupling:** match authorized Qobuz/Audius/JioSaavn/addon
   sources against the selected recording. A source declares codec/length/
   transport with independently validated quality. Audio engine only
   receives a verified stream; YouTube playback may remain as a deliberate
   legacy fallback or separate Video tab, without giving identity to songs.
5. **Separate discovery UI:** compare catalog coverage for e.g. Bad Bunny,
   Metro Boomin, Zoé, regional/independent releases, live/remix and multi-
   credited tracks; test artist/release dedup, missing metadata, languages
   and ambiguity. Only then flip a feature flag for new-search users.
6. **Dual-read, dual-write migration and rollback:** maintain compatible
   playlists/likes/saves; production user data must survive a rollback.
   Audio QA, offline QA, privacy, provider terms and quota tests must pass.
7. **Retire legacy catalog only after** coverage, migration and on-device
   equivalence are validated. Do not delete SwiftyTube/InnerTube now:
   playback, playlists, sync and videos still depend on them.

## Test

Run `bash scripts/test-musicbrainz-identity-catalog.sh` on Swift 6,
or review the isolated GitHub Actions check. The tests are **mock-only**:
no live MusicBrainz API, no copyrighted audio, no credentials, no iOS
device. A passing test does not establish catalogue completeness, commercial
API permission or safe migration of an existing Trop library.
