# Trop Library V2 — make YouTube an optional audio provider

**Architecture decision — 22 November 2026.** Implement the transition
alongside Library V2 on Trop, but keep the current combined restore on draft
PR #80 internal and disabled until the migration/restore gate passes.

## Product contract

- Trop owns **recording, artist, album, playlist and playlist-entry identities**.
  Radio and podcasts are first-class, independent audio sections. A provider
  supplies metadata and/or a playable audio rendition, not the identity of
  the user's library.
- **YouTube has one allowed product role: an optional source of audio tracks**.
  Its absence, account logout, network failure, API change or removal must not
  block launch, Library V2 reads/writes, playlists, likes, local search, backup,
  restore, radio favorites, podcasts, downloads already available locally,
  or audio from other providers.
- **No YouTube Music account login, subscription sync, remote library mutation,
  feed, Explore, video catalogue or YouTube personalization is required** for
  the core product. Any optional YouTube track lookup should be clearly
  provider-scoped and never silently own the user's data.
- Audio-only is deliberate. Legacy `song.is_video` is a migration diagnostic
  only, not a new Library V2 field or video playback capability.
- Actual independent stream availability is a **separate contract**:
  library metadata can survive even when no provider can play a track.
  Display a truthful unavailable/missing-source state; do not invent streams,
  silently substitute a different recording or delete the library item.
- Other providers may require their own optional permissions/configuration;
  users can choose providers and formats. Respect explicit Hi-Res and Atmos
  toggles and quality policy, never silently bypass them.

## Verified code-level dependency inventory at PR #80

| Surface | Evidence at current source | Cutover requirement |
| --- | --- | --- |
| V2 data storage | `TropLibraryV2Store.swift` uses Trop UUIDs and optional `source_alias`; local writes do not call YouTube | Keep ownership; permit adding/removing aliases without changing saved UUIDs |
| Legacy migration | `TropLibraryV2LegacyImporter.swift` reads legacy rows and currently stamps `provider: "youtube"`; old video-backed music IDs may be ambiguous | Classify recordings, preserve likes/ordered memberships, quarantine unclear video-only records without silent deletion; never make a YouTube alias mandatory |
| Existing account barrier | `TropLibraryV2AccountIsolation.isEnabled` uses `trop.library.v2.previewEnabled`; `SyncBridge` blocks legacy sync only when V2 flag is on | Make this a permanent library ownership policy rather than a preview toggle; disable legacy sync/mutations before default V2 rollout |
| Legacy library UI | `Trop/Library/LibraryView.swift` still calls `restoreSession()`, `fetchAccountInfo()`, `SyncBridge.forceFullSync()` and remote playlist delete | V2 library path does not initialize the YouTube account client or call remote mutations; local playlist deletion stays local |
| Settings and login | `Trop/Settings/SettingsView.swift` hides account section only in V2 preview mode | Remove mandatory account entry from the eventual default experience; YouTube audio discovery never needs a library login |
| Search | `SearchViewModel.fetchResults` awaits `SearchService.shared.search` (InnerTube) **before** launching Audius/Qobuz/JioSaavn/add-on searches | Search V2 locally first, then start independent providers concurrently with isolated errors/timeouts; YouTube may be disabled and no request should be necessary |
| Home / Explore | `HomeViewModel` and `ExploreViewModel` use `InnerTubeClient.browse` for content feeds; `HomeScreenView` still has a legacy sync/account path | Build provider-neutral Home/Explore or safely omit unavailable sections; no default InnerTube request for core Home |
| Playback resolution | `MusicCatalogTrack` is source-scoped, but `MusicPlaybackIdentity.isYouTube` treats every colon-free ID as YouTube; `PlaybackManager` has YouTube-first / YouTube-fallback quality paths | Route by explicit source aliases + recording UUID, not `SongItem.videoId` naming; enforce provider choice, quality, cancellation and no-YouTube mode |
| Likes | `LikeStore` retains legacy YouTube remote-like branches; V2 local route already exists | Every V2 like/unlike is local; no remote mutation, regardless of original provider |
| Radio | `TropLibraryV2RadioStore` and `RadioPlaybackCoordinator.playSaved` are independent of account sync | Test saving/playing Radio Paradise/FIP and other stations with YouTube disabled; never persist expiring stream URLs |
| Podcasts / future audiobooks | V2 includes independent podcast/episode metadata, source discovery planned later | Never connect their identity to YouTube Music; catalogue-provider research is a later phase |

**Important distinction:** A provider-free *metadata* round trip already
passes isolated GRDB tests. The code inventory above shows that Home, search
and existing playback flows are **not yet independently provider-neutral**.
Do not describe the YouTube dependency removal as completed.

## First implementation slice — provider-independent search (22 Nov 2026)

Under **Library V2 preview mode**, SearchViewModel now refuses to query
InnerTube for the YouTube Music catalogue or typeahead suggestions, and it
does not reuse cached legacy YouTube search sections. Explicit searches
launch **Audius, Qobuz (if configured), JioSaavn and enabled music add-ons
concurrently**. Each provider publishes its audio results as soon as it
finishes rather than waiting for YouTube or the slowest other source.
Cancellation and current-query guards prevent old provider results
from contaminating a newer search. The legacy search behavior stays
available behind the old-library mode solely for a safe migration period.

This was **not** the final provider-neutral catalogue at that stage.
The later Home/Explore and V2-local-search slices below supersede those
particular dependencies; playback/queue still contain YouTube assumptions.
No new YouTube audio-discovery API or persistent music metadata index was
implemented in this slice. Test the provider-only mode and incremental
arrival on an iPhone **after** CI and a consolidated QA candidate, not
with a series of user installs.

## Second implementation slice — V2 Home and Explore (22 Nov 2026)

Under experimental Library V2, **Home now reads Trop-owned saved
recordings, playlists and radio favorites directly**, with navigation to
local playlists and Search. A saved recording is displayed as metadata,
not played by guessing a YouTube source from its Trop UUID; radio stations
continue to use the dedicated radio catalogue resolver. It also exposes
downloaded audio without creating a YouTube session.

V2 **Explore no longer fetches YouTube Music's mood, genre, chart or
trending shelves**. It offers entry points to independent audio-provider
Search and the local library, while accurately marking native Trop charts
and recommendation indexes as forthcoming. This is a temporary honest
discovery surface, not a claimed replacement catalogue.

The existing YouTube Home/Explore feeds remain temporarily in legacy
mode for safe migration. Both models have V2 gates in addition to view
routing, and both skip the old YouTube session bootstrap in V2. Explicit
user data, like states, local files and legacy account data are left
untouched. Home's old **offline-downloads-only** CI policy is replaced by
a stronger policy: V2 metadata may be displayed locally but must NEVER be
played using an unresolved YouTube ID; only the separate DownloadsView
may play verified file URLs. The UI still needs on-device QA after Xcode
CI succeeds.

## Third implementation slice — search the actual V2 saved library (22 Nov 2026)

Search under experimental Library V2 now loads **Trop-owned recordings,
playlists and saved radio favorites**, rather than calling
`SearchService.localSearch` against legacy YouTube-keyed song/playlist rows.
Title, artist and radio subtitle matches use locale-aware case/accent
insensitive text containment. The Library filter and unfiltered results show
those local items even when no remote provider succeeds; stale search tasks
cannot publish into a different query. The non-V2 legacy search stays intact.

**Recording rows are intentionally metadata-only:** saved V2 UUIDs are not
passed to `YTItem` or the YouTube-first playback router. Playlist matches
navigate to the Trop-owned V2 playlist screen; radio matches use the dedicated
saved-station resolver and show a truthful offline failure rather than
persisting a stream URL. External provider search stays independently
playable as before.

Current implementation reads V2 lists and limits displayed matches to 80
recordings, 40 playlists and 40 radios. A properly indexed, scalable
music-catalogue search (including artists/albums/podcasts and verified aliases),
recording playback from V2, and refresh after mutations remain follow-ups.
This is not the final catalogue and does **not** authorize migration, restore
UI or removing YouTube legacy data. Swift 6 search-policy checks, view wiring
checks and the integrated iOS Nightly must pass before any physical QA claim.

## Fourth implementation slice — explicit V2 saved-audio playback (22 Nov 2026)

Library V2 now offers play actions for saved recordings in Library and Search,
and for playlist entries. A read-only GRDB source-alias query resolves a saved
Trop recording UUID to an explicit global provider-scoped audio ID. The first
slice admits only Audius, Qobuz, JioSaavn and enabled music add-ons; a missing,
account-scoped, metadata-only, legacy YouTube or ambiguous alias **does not**
produce a guessed playback ID. In CD/lossless mode, known lossy-only providers
(Audius, JioSaavn) are rejected. A user-visible message keeps all saved
metadata and playlist memberships intact when playback cannot begin.

Playlists preserve ordered membership UUIDs, including intentional duplicate
recordings. The route preflights every entry before replacing the queue; no
unresolved entry is silently dropped. Existing provider resolvers determine
whether a real stream is available. Network/service failure can still occur
after this preflight and is handled by the current player path; this requires
physical-device QA before claiming complete missing-source UX.

The V2 add-on route now rejects YouTube-backed resolutions unless/until an
explicit optional YouTube-audio source policy is established. Provider-scoped
IDs do not enter the legacy YouTube-keyed upgrade-prefetch chain. These
restrictions deliberately leave legacy mode untouched. A V2 metadata alias
does not confer licensing, stream rights or proof that another rendition is
the same recording. There is **no automatic cross-provider matching** yet.

Acceptance remains gated on isolated Swift 6 policies, source wiring checks,
iOS Nightly and iPhone QA. This does **not** enable real restore, import or a
default V2 switch and does not claim complete quality/routing compliance.
Full download-file identity, source choice among multiple valid renditions,
album/artist V2 playback and provider failover need later dedicated gates.

## Fénix II physical QA — restored playback and artwork (22 Nov 2026)

The first iPhone restore via combined V6 snapshot and external Telegram
document passed: 25 V2 recordings, 4 playlists, 10 entries, 1 favorite radio,
and user-confirmed persistence after reopening Thrum. **The next on-device
recording exposed a previously existing V2 limitation:** saved tracks display
placeholder music-note icons and the **"Audio unavailable — This song has no
verified independent audio source yet"** alert when tapped. **User clarification
(22 Nov): this behavior already occurred when saving songs before the restore
test.** Do not classify either symptom as regression caused by the backup,
uninstall/reinstall, or restoration. The evidence directly establishes
pre-existing missing artwork; user reports the saved-song experience as a whole
was already like this.

These are separate V2 product-completeness issues, not a failure of recovery:

- **Artwork:** earlier V2 UI intentionally had no image representation or
  lookup. The current PR now enriches saved V2 tracks in Recently Added,
  Songs and playlist rows through the existing independent
  `MetadataResolver` (iTunes, Deezer, MusicBrainz), accepting only matching
  title+artist and HTTPS artwork. Covers are display-only and are not yet
  portable in the backup; no YouTube catalogue is required. Missing/mismatched
  results retain placeholders. CI and new iPhone QA are still required.
- **Playback:** V2 playback accepts only verified global Audius/Qobuz/
  JioSaavn/addon source aliases; the backup deliberately omits potentially
  private addon IDs, and the policy currently excludes YouTube aliases to
  avoid implicit YouTube fallback. Therefore restoring saved metadata does
  **not** imply that each track has a playable audio source. Never guess by
  title or silently re-enable YouTube. Implement explicit source-relinking
  and/or explicitly opted-in provider audio with separate QA while retaining
  all restored songs and playlist memberships.
- **No destructive QA:** do not ask the user to uninstall the restored library
  again. Verify covers in a new beta, and source relinking as a separate
  feature. Keep PR #80 DRAFT until complete.

## Fénix II — metadata-driven audio relinking (22 Nov 2026)

The user clarified that the missing artwork/unplayable saved recordings
**already existed before uninstalling Thrum**. This is V2 playback/UX debt,
not a failure of the successful Fénix metadata restore.

**First opt-in implementation slice (PR #80 DRAFT):**
- Tapping a V2 recording without a usable independent source opens **Find audio
  source**; playlist entries expose the same action in their context menu.
- Trop searches **Audius, authorized Qobuz, JioSaavn and up to four enabled
  music addons** from the recording's saved title and artist. Search is
  parallel, no YouTube Music catalogue call, account bootstrap or background
  mutation. Results lacking title/artist agreement, an appropriate edition,
  available duration evidence or supported quality are excluded. Results are
  **candidates, not verified stream URLs**; no implicit autoplay.
- The user must choose a track explicitly. Inside one GRDB write, Trop
  re-reads the current recording and checks source identity again, prevents an
  alias already owned by another recording, is idempotent if already linked,
  and declines to create ambiguous extra active sources. The recording UUID,
  liked state, playlists, ordered entries and backup metadata are left intact.
  Playback then uses the existing normal ApoloEngine router.
- **Current limitations:** no automatic bulk relinking, no provider choice
  switching when an independent source is already linked, and a catalogue
  match does not establish stream availability. The chosen addon alias may
  contain private installation identifiers; it **remains intentionally omitted
  from portable backups** and may require relinking on future reinstalls.
  Title/duration metadata cannot prove two different masters are identical,
  even with strict matching; the user confirms the match.
- Strict Swift 6 match-policy tests, UI wiring checks and integrated Nightly
  are needed before device QA. **Do not claim this feature works in the user
  IPA until a new CI-validated beta is installed and tested.** Never clear the
  restored database or silently re-enable YouTube fallback.

## Trop Match — saved-library prelink slice (22 Nov 2026, PR #80 DRAFT)

**Source of truth remains Library V2 metadata and UUID; these prelinks are
best-effort provider associations, not downloaded audio or codec proof.**

- After a successful `createItem(recording)`, `savePlaybackRecording`, or
  `saveToPlaylist` GRDB transaction, Trop schedules an asynchronous prelink
  of the saved recording. Save/Like/Playlist operations succeed without
  waiting for any network request; provider failures cannot roll back them.
- Opening Library V2 or its Songs screen schedules **at most six recent saved
  recordings**; the coordinator caps its queued IDs at 16, runs one provider
  search at a time, remembers recent attempts for 30 minutes per app process,
  and does **not** iterate a 480+ song archive or the Home feed.
- No prelink without valid normalized performer/title and **known duration
  (at least 30 seconds)**. Only `TropMatchCandidatePolicy.exact` is eligible:
  edition hints such as live/remix, ambiguous timing, wrong artist and
  YouTube-catalogue candidates are excluded from automatic linking.
- Existing provider references are never deleted or replaced. Up to **two**
  candidate aliases can be added per pass, with a cap of three automatic
  independent source aliases per recording and per-provider duplicate limits.
  A stored YouTube video ID may be retained as an optional audio source but
  is never queried to construct the catalogue.
- Every candidate goes through `TropLibraryV2Store.linkConfirmedAudioSource`,
  which re-reads the current GRDB row and checks provider-ID ownership in
  the write transaction. If a recording changes, disappears or collides with
  an existing owner, linking fails without losing the song, like, playlist
  or downloaded file. No popup and no autoplay on prelink failure.
- Library V2 prelinks persist as safe provider IDs, **not** expiring signed
  playback URLs; future dynamic resolution still applies the *current*
  quality setting and verifies actual addon audio. No Hi-Res/Dolby
  representation is inferred from a search label.
- Home, Explore and Search remain **dynamic**. They MUST NOT call the
  persistent V2 prelinker while rendering/recommending transient items;
  temporary queue prefetch and on-demand resolution are separate work.
- **Still pending:** true resumable background/batch import matcher,
  incremental rechecks after addon installation/quality changes, source
  health/expiry records, Stream-first recovery, robust switching across
  failed sources, metadata collision auditing, audio startup latency,
  and physical iPhone QA. CI covers policy; never call this a release
  or full Library V2 independence before the integration gates pass.

## Trop Match — first integrated implementation (22 Nov 2026, PR #80 DRAFT)

Trop Match is distinct from a music catalogue, source transport and ApoloEngine:

- **Stable library identity:** recording UUIDs, likes, playlists, ordering,
  downloaded files and metadata backups must never change because a provider
  match is missing, rejected, or approved.
- **Discovery:** when a saved song cannot be played with its current compatible
  aliases, Trop queries the configured independent audio providers by title
  and artist. The on-Play path uses a strict exact-recording classifier and
  can create a provider alias automatically. It does not open a modal on a
  normal Play tap. No automatic query of the YouTube Music catalogue.
- **Version evidence:** matching uses normalized artist/title, version markers,
  duration tolerance and release-title hints when provided by addons, Qobuz
  and JioSaavn. Live/remix, suspicious release editions, unknown timings and
  other plausible alternatives are **review-only**. An album cover image is
  not authoritative edition metadata; test real-world false positives.
- **Review UI:** the song's long-press menu opens *Review Audio Sources*,
  separating verified candidates from *Review Alternatives*. Approving an
  alternate requires a second explicit confirmation. Such links use
  `source_scope=user-approved-alt`, preserving that they are NOT an
  exact match. The original recording is NOT overwritten or re-identified.
- **Multiple audio links:** `trop_v2_source_alias` retains existing source
  rows and may link additional confirmed audio IDs (bounded; non-destructive,
  conflict-guarded). Playback selects an exact source ahead of approved
  alternatives; current quality preferences influence provider ranking.
  This does **not** guarantee the actual bitrate/codec of an addon stream:
  resolving the URL must still check its format before claiming CD, Hi-Res
  or Atmos. Resolving a fresh provider link remains best effort.
- **Optional YouTube audio:** off by default under Settings → Experimental
  Library → YouTube as optional audio source. When enabled, a pre-existing,
  valid saved YouTube video ID may be used as an audio transport for quality
  modes permitting compressed audio. CD/Best FLAC never accept YouTube as
  lossless. This is not a YouTube Music library, login, bootstrap or search;
  newly imported provider-neutral recordings without a saved YouTube ID
  cannot yet discover YouTube audio. No silent YouTube fallback.
- **Future work / not delivered in this slice:** a resumable 480+-track
  batch matcher on imports and addon changes, offline-safe playback fallback,
  independent quality-capability proof per provider/codec, source health and
  expiry, background throttling, changes while a song is playing, automatic
  playlist rematching and full UI for importing/reviewing candidate sets.
- **Validation gates:** strict Swift 6 tests cover exact vs live/remix, wrong
  artist, duration mismatch, provider security, YouTube opt-in and source
  choice; integrated iOS Nightly and real-device QA are required. Do not
  tell the user to uninstall Thrum or claim this works on their phone until
  the new beta has passed CI and device checks.

## Coupled implementation order — no extra user-facing IPA churn

1. **Safety baseline:** finish PR #80 restore validations, portable backup,
   import conflict preview, origin remapping, no-user-data-loss tests and
   canonical music-only classification. Keep legacy rows untouched; ensure
   an unresolved legacy item remains reviewable, not silently discarded.
2. **V2 as product library:** switch primary user routes and favorites to
   V2-owned UUIDs, not raw YouTube IDs. Add provider-independent track models
   to queue, Now Playing and download references without regressing ApoloEngine.
3. **Provider orchestration:** introduce a common audio search/resolution
   interface; launch providers independently, with YouTube opt-out. No
   provider may be a hidden required bootstrap, search barrier or fallback.
4. **Detach legacy account features:** stop automatic InnerTube account
   restoration, periodic/full legacy library sync, remote likes and playlist
   mutations once V2 is active. Remove account UI and provider-specific
   Home/Explore assumptions from the default path; keep any legacy read-only
   import tools isolated for recovery.
5. **Source matching:** retain optional aliases as evidence of a known
   recording, link safe alternatives only with explicit identity verification
   and no unauthorized or mistitled substitution. Respect lossless, Hi-Res
   and Atmos user toggles independently of the chosen source.
6. **Final combined candidate:** after CI and iPhone QA, deliver backup +
   Library V2 migration + provider independence together. Any iCloud work
   requires a separate proven transport/entitlement plan; do not claim an
   arbitrary sideloaded IPA can use it. Merge only after explicit approval.

## Acceptance tests required before replacing the existing library

- **YouTube unavailable** (network blackholed/disabled, no cookies and no
  signed-in account): app starts, Library V2 loads, saves a favorite, creates/
  edits/deletes a playlist, restores an isolated backup and searches local
  recordings. Zero mandatory calls to InnerTube in these operations.
- **Independent search:** Qobuz (if configured), Audius, JioSaavn and enabled
  add-ons show results even when YouTube hangs, fails or is disabled. The
  first result does not wait for a YouTube timeout.
- **Independent audio:** play an available non-YouTube recording via Apolo,
  background/lock-screen Now Playing and Apple audio-session interruption
  recovery. A missing stream shows "unavailable" rather than routing
  silently to YouTube.
- **Provider quality:** selectable lossless/CD, optional Hi-Res, optional
  Atmos; no upgrades or lossy fallbacks that violate the active mode.
- **No remote writes:** instrumentation asserts zero YouTube remote library
  likes, deletes, playlist edits or session bootstrap across every V2 action.
- **Music-only migration:** liked legacy song whose original source was a
  video but music is verified -> recording; genuine video or ambiguous row
  -> flagged for review with original legacy data, likes and memberships
  preserved. Never create a V2 video kind.
- **Radio and podcasts:** favorites survive export/restore and radio playback
  works with YouTube disabled; podcasts retain saved/episode relationships.
  Stream resolution, real-world playback and iCloud sync require separate QA.
- **Migration rollback:** malformed, partial or ambiguous imports fail without
  deleting existing Library V2 or legacy data; repeated imports are idempotent.
- **No extra manual installs during development:** rely on PR CI and the
  Nightly pipeline until a single integrated beta is safe to test.

### Non-goals during this stage

Do not remove ApoloEngine codec routes, enable experimental Restore,
convert videos into music blindly, promise catalogues we haven't sourced,
or implement podcast/audiobook discovery before core migration is complete.
