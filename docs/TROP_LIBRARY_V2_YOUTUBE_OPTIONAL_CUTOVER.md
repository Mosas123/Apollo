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

This is **not** the final provider-neutral catalogue. Local search still
uses legacy song/album/artist rows, Home/Explore are still sourced from
InnerTube, and playback/queue routes still contain YouTube assumptions.
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
untouched. The UI still needs on-device QA after Xcode CI succeeds.

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
