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
