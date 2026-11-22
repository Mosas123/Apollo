# Trop combined metadata archive — experimental stage

**Status (draft PR #80):** Combined export and file verification have passed
real iPhone QA. The isolated in-memory reconstruction of a real iPhone archive
also passed, rebuilding **24 V2 recordings, 4 playlists, 10 playlist entries**
without writing to the active library. This validates metadata restoration
logic, **not** production device recovery or downloaded media.

## Files backup and verified rehearsal

- **Combined Metadata Snapshot** under Settings → Experimental library exports
  the old+V2 metadata together in a single GRDB read transaction. The user
  chooses a Files, iCloud Drive or other available document-provider location.
- Both the UIKit Files picker and On My iPhone → Thrum local scanner can verify
  the archive with a 40 MiB limit, checksum and strict metadata validators.
- **Test latest saved copy in isolated memory** reconstructs the archive into
  a temporary in-memory SQLite database with the actual app migration schema.
  It verifies the restored records, ordering, dates and duplicate memberships
  without reading or writing the live library. This passed real-device QA.
- Neither operation includes downloaded audio, account logins, listening
  history or private provider links; private aliases may be excluded. SHA-256
  is neither encryption nor authentication. Keep an extra copy of the file.

## Fresh-install-only restoration — not yet validated on a device

The experimental Combined Snapshot screen links to **Restore Library**, with
all of these safety constraints:

1. An eligibility read checks that the database is persistent and **every**
   protected legacy/V2/music/history/download table is empty. On the user's
   existing 24-recording library the restore action **must remain disabled**.
   The UI never offers a reset, replacement, or deletion.
2. Only after eligibility does the user choose a combined archive with the
   copy-mode UIKit document picker. A bounded file read verifies checksum,
   format, record relationships and counts **before** a preview can appear.
3. The user explicitly confirms the import after viewing summary counts and
   a warning that no downloaded audio or private connections are recovered.
4. The production `restoreIntoEmptyLibrary` performs fresh archive validation
   and `TropLibraryCombinedRestorePreflight.requireEmpty` **inside one atomic
   GRDB write transaction**. If anything was added between the UI preview
   and confirmation, the transaction aborts without changing the database.
5. Success reports saved metadata counts and refreshes the local library.
   Failure does not invoke a reset, delete, remote sync or destructive merge.

**Release gate:** This user-facing restore is currently staging-only on
draft PR #80. It must pass exact-commit CI, an empty-container on-device
restore/relaunch test, blocked-occupied-container tests and a Files-provider
selection test **before** being considered ready. Do **not** delete or reinstall
Trop to test this feature; the current installation cannot and should not
be made eligible by erasing user data. iCloud Sync is separate future work.

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

- Format: `trop-library-combined-metadata`, version `6` (internal, not
  released to users). Earlier combined v1/v2 prototypes were not shipped.
  The standalone legacy v1 and standalone Library V2 v2 formats are unchanged.
- JSON with sorted keys, dates in milliseconds and SHA-256 over the canonical
  payload. This is **corruption detection, not encryption/authentication**.
- Payload consists of `legacy` and `libraryV2` snapshot objects, the original
  `legacyMemberships`, a stable installation-local UUID `originScope`, and
  `foreignTombstones` scoped to their original installation.
  V6 adds local `podcastArtists` (true `artist.is_podcast_channel`)
  and `episodePodcastNames` (validated `episode.podcast_name`).
  These display/classification hints survive without provider aliases
  or auto-starting remote sync. Standalone legacy V1 remains unchanged.
  V5 additionally captured optional `legacyAlbumSources` (`album.playlist_id`)
  and `legacyArtistSources` (`artist.channel_id`) as public source hints
  owned by bookmarked legacy albums/artists. They are NOT local playlist
  foreign keys, and V2 will not require the source provider to be enabled.
  Signed URLs, query tokens and unsupported source identifiers are rejected.
  V4 added ordered `podcastEpisodeMemberships`, plus minimal metadata for
  unsaved/unsubscribed referenced podcasts and episodes. This preserves
  the legacy `podcast_episode_map` without inventing saved/subscribed dates;
  its links must have existing parent and child records or export fails.
  The standalone legacy V1 archive is unchanged. Both library sections pass their existing
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
specific to **one database**. The combined v3 envelope captures the
original row-ID-to-playlist/song/position map in the **same** GRDB read;
PR #67 standalone legacy backup v1 does not include these IDs.

**V13 add-only migration:** `trop_v2_library_origin` stores a random
installation UUID, not a device hardware ID. The separate
`trop_v2_foreign_import_tombstone` table stores imported-at metadata
with `origin_scope + source_membership_id` as its primary key. This
separate namespace prevents old deleted-membership IDs from colliding
with SQLite IDs on a different installation. No old rows are dropped.

Orphaned legacy ledger rows can now be **retained as scoped foreign
tombstones** rather than being discarded or assigned fictional local IDs.
Their source UUID and optional V2 entry reference survive a combined
backup/re-export. This is still internal, without a user restore button,
and it does not guarantee playable audio or all production migrations.

### Read-only destination remapping prototype

`TropLibraryCombinedRestorePlanner` now validates an explicit
**source membership → SQLite-assigned destination ID** mapping. It verifies
the exact playlist/song/position identity, checks completeness, positive
destination IDs, unique sources and unique destination IDs, then builds a
**new V2 import ledger in memory** using only mapped destination IDs.

The planner maps only *live* source memberships to local SQLite IDs.
An orphan from the V2 import ledger becomes a scoped tombstone under
`source.originScope`; existing foreign tombstones are carried forward.
Duplicate origin+ID keys fail validation. Missing/foreign/mismatched live
rows still fail closed. The planner performs no database writes and does
not enable restore UI.

`TropLibraryCombinedRestorePreflight.requireEmpty(db)` adds a separate,
read-only GRDB safety check intended to run **inside the eventual single
restore write transaction** (never as a racy earlier read). It refuses a
partially migrated destination and refuses any existing rows in protected
legacy music, playlist, artist, album, podcast, history, speed dial,
downloaded-track and all six V2 tables. It performs no deletion, resetting,
migration, importing or restore; a valid empty schema is required.

The GRDB fixture separately tests fresh SQLite `AUTOINCREMENT`-assigned IDs
that differ from the original source ID, verifies the remapped ledger and
proves an injected failure after a valid remap rolls back a sandbox
transaction. This is not on-device QA.

Remaining design: compatibility with earlier experimental archive
versions, proof against production migrations and schemas, complete
roundtrip of all metadata, idempotence guarantees and on-device QA.
There is no user-facing restoration pathway.

### Internal sandbox restore implementation

The experimental TropLibraryCombinedRestoreStore now composes the existing
empty-destination preflight, legacy metadata insertion, SQLite-assigned
membership IDs, origin-scoped foreign tombstones and all six V2 metadata
tables in ONE GRDB write transaction. It is **not connected to UI** and
does not overwrite an existing library. The GRDB fixture now covers
failure during foreign-tombstone insertion, late SQL failure with legacy
and V2 rollback, scoped metadata re-export and repeat-restore refusal.
These are test claims to verify in the latest CI.

**Limits:** it cannot restore audio, history, downloaded file paths, tokens
or private addon aliases, even when tombstone metadata survives.
Legacy episode/artist/album relations beyond the existing allowlisted metadata
and migrations still need deeper restore audits before user release.

**Audit 22 Nov:** the legacy V1 archive filters podcasts to subscribed rows
and episodes to saved rows, and did not include the ordered
`podcast_episode_map`. Combined V4 now preserves that relationship, including
unsaved/unsubscribed items it references. GRDB fixtures check exact link order,
all associated podcast/episode metadata, and the independent radio favorite
`station_uuid`/name/date across restore and re-export; no radio stream URL
is archived. These tests do not establish playback/Now Playing or iPhone QA.

**Audit of album/artist source links (22 Nov):** real legacy migrations
include `album.playlist_id` and `artist.channel_id`, which the legacy V1
metadata-only backup does not capture. Experimental combined V5 preserves
the public identifiers as optional provider references, never as canonical
Trop IDs or required YouTube logins. GRDB fixtures now test these links
across source export, isolated restore and re-export, alongside podcasts
and radios. Private playlists, signatures, URL parameters, credentials
and streaming manifests remain excluded.

**No-provider regression (22 Nov):** the GRDB fixture additionally
restores an internal combined metadata archive with **zero provider aliases,
zero YouTube legacy relations and zero optional album/artist source IDs**.
It verifies Trop-owned playlists, ordered podcast/episode relationships and
radio favorite station IDs across restore and re-export, and checks the
archive never contains "youtube", private addon manifests or a stream URL.
This is a test of metadata independence; it does NOT validate playback,
source resolution without YouTube, radio connectivity, or real iPhone restore.

## Legacy field audit — preservation versus provider state (22 Nov 2026)

This classification is grounded in the shipped legacy schema
(`Trop/Database/DatabaseMigrations.swift`), GRDB entity models
(`Trop/Database/Entities/*.swift`), the actual snapshot allowlist and the
additive sync mappings in `Trop/Services/TropLibraryStore.swift`.
It is a **review/policy proposal**, not a change in the archive payload.
Do not bump the combined envelope or enable restore until tests prove each
selected field's round trip under real migrations.

| Field(s) | Observed meaning | Recovery decision |
| --- | --- | --- |
| `song.liked`, `song.in_library`, `song.create_date` | Local favorite/library membership and original creation date | Already covered by legacy V1 metadata; keep |
| `song.total_play_time` | Locally accumulated listening time, preserved by `SongEntity.merging` | Valuable user state; **currently missing** from archive. Decide whether listening history belongs in a separate opt-in backup before exporting |
| `song.is_uploaded` | Legacy upload-origin flag, preserved on merges | Preserve as historical provenance only; do not claim uploaded media remains playable |
| `song.is_video` | **Legacy YouTube video-classification flag**, preserved on old song rows | **Do NOT migrate as a V2 media type or feature.** Music-only catalogue: inspect this flag only while classifying old rows, and never automatically expose videos as recordings |
| `song.modify_date` | Legacy modification date | Candidate to preserve for sorting/conflict semantics; currently synthesized as `createdAt` during combined restore |
| `artist.is_podcast_channel` | Distinguishes a podcast channel; sync deliberately retains existing value | **High-priority safe field** for a future combined format; do not turn it into a required remote channel login |
| `album.is_uploaded` | Legacy upload provenance retained by album sync | Preserve optional origin semantics, not file bytes |
| `album.song_count`, `album.duration` | Cached album summary derived from remote catalogue | Optional historical display fallback; treat as nonauthoritative and revalidate rather than forcing it to be correct |
| `playlist.is_auto_sync` | Explicit automatic sync behavior; provider sync may set it to true | **Never re-enable automatically after restore**. If intent is preserved, require a separate user opt-in before any remote synchronization |
| `playlist.remote_song_count` | Provider-reported playlist count | Optional stale display hint, not an authoritative membership count |
| `episode.podcast_name` | Optional display fallback when podcast entity is unavailable | Candidate for safe metadata allowlist, with validation and no mandatory provider |
| `playlist_song_map.set_video_id` | Legacy remote edit/mutation identifier | **Exclude** from portable archive; do not replay a remote playlist mutation |
| `song.library_add_token`, `song.library_remove_token` | YouTube-side library mutation credentials | **Strictly exclude**; never restore or log |
| `thumbnail_url`, `format.playback_url`, downloaded paths | Provider artwork / ephemeral media URLs / local device paths | **Exclude**; regenerate artwork and resolve playback via active provider; audio downloads require a separate design |
| `event`, `play_count` | Playback history | Not part of this metadata-only archive; assess separate optional privacy and retention policy |

The combined v5 already captures bookmarked album `playlist_id` and artist
`channel_id` as public optional provider hints. It also includes live
playlist memberships, podcast/episode links, foreign tombstones and radio
favorites. **Nothing above changes the standalone legacy V1 or V2-only V2
archives.** The next implementation slice should be the clearly local and
privacy-safe fields (`artist.is_podcast_channel`, `episode.podcast_name`,
upload-origin provenance and original modification dates), explicitly **excluding**
video-catalogue behavior, with strict validation
and GRDB regression fixtures. A no-YouTube recovery must preserve local
playlists, ordered podcast episodes and radio favorites without starting
sync, silently discarding metadata or inserting remote credentials.

**V6 local podcast metadata (22 Nov):** artist `is_podcast_channel` and
episode `podcast_name` are now included in the internal combined transport.
Only bookmarked artists and saved/linked episodes can own these records.
A stale/unowned ID, duplicate or URL-shaped podcast name is rejected.
Real GRDB fixtures use positive values for both saved and unsaved episodes,
check exact restore/reexport with source metadata and again without any
YouTube/provider aliases, plus the existing radio checks. This is
**not on-device QA**; latest CI must pass before calling it verified.

## Music-only catalogue policy — user decision (22 Nov 2026)

**ApoloEngine / Trop are becoming a music-first, Trop-owned catalogue, NOT
a YouTube Music or video catalogue.** The target library represents music
recordings with Trop-native identities, artists, albums and playlists.
Radio stations and podcasts/episodes remain separate native sections.
There is **no video browsing, video playback or video media type** in the
target catalogue. YouTube IDs and old `song.is_video` values cannot turn a
video into a first-class V2 library item or become required for music access.

For safe migration, **legacy rows are not necessarily pure videos just
because their original YouTube source was video-backed**. Separate
classification from preservation:

- Migrate verified music recordings as audio-first, provider-independent
  entries, preserving user likes and ordered playlist references.
- Put genuinely video-only or ambiguous legacy rows into an explicit,
  read-only migration report / unresolved queue until confidently matched
  with an audio recording. Do not auto-convert them into music, and **never
  silently delete a liked row or playlist membership**.
- Keep old video-only provenance confined to the legacy migration reader
  if necessary for that classification. **Do not add `is_video` to the
  V2 portable archive, new catalogue model, playback routing or UI.**
- A future YouTube Music removal must not prevent export, restoration,
  playlist editing, radio favourites or podcast access. Independent music
  source resolution and actual playback need separate on-device QA.
- No change here alters the existing archive, deletes user data, merges
  drafts or enables experimental restore.

**Parallel requirement — optional YouTube provider:** Library V2 and
the de-YouTube cutover are one coordinated migration, not separate user
installations. The audited source-of-truth, explicit blockers, compatibility
rules and acceptance gates are in
[`TROP_LIBRARY_V2_YOUTUBE_OPTIONAL_CUTOVER.md`](TROP_LIBRARY_V2_YOUTUBE_OPTIONAL_CUTOVER.md).
Do not remove legacy YouTube support before verified backup/import, and
do not introduce a video catalogue or rely on YouTube for library identity.

Before any public Restore action:

1. Validate V13 origin identity and foreign-ID mapping on fresh/upgraded
   production schemas, refusing all ambiguities or duplicate origin keys.
2. Preserve legitimate duplicate playlist positions (V2) while respecting
   legacy uniqueness rules; never de-duplicate across independent namespaces.
3. Validate the internal all-or-nothing **legacy+V2** GRDB restore against
   actual production schemas and isolated targets. Forbid overwrites on an
   installed library, repeat restores and verify injected-error rollback.
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
both legacy and V2 rows, captures actual SQLite-assigned membership IDs,
checks scoped orphan preservation and rollback after failed tombstone insertion,
and verifies destination-preflight guards on missing schemas, legacy rows
and downloaded-track data.
CI is not an on-device restore test; check the HEAD workflow result before
calling the new fixture passed.
