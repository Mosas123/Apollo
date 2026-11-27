# Apollo Music Addons — Manager UI & Fast Playback Design (Draft)

## Objective

YouTube Music remains the **primary signed-in account, recommendation
engine, library and first-party music view**. Addon catalogs are separate,
opt-in sources that may expose licensed tracks, recordings of live
performances, lyrics, metadata and other content. Show an explicit source
label on every non-YouTube result.

**Do not silently replace or modify the audio of a YouTube video.** Such
combinations can conflict with YouTube API developer policies. External
audio must be represented as its own provider-owned result with correct
provenance and rights; an authorized independent catalog may appear
alongside YouTube search results, not disguised as YouTube audio.

## UI implementation (this PR)

Inspired by the *screen organization* of the GPLv3 NuvioMobile manager
(overview, add-by-URL, installed cards), but implemented independently in
native SwiftUI. No Kotlin source or Nuvio branding/assets copied.

Settings → Integrations → Music Addons:
- YouTube Music remains visible as the default source.
- Summary counts: installed, enabled, capable of audio.
- Enter HTTPS manifest URL, fetch metadata only, validate manifest and
  review requested capabilities before installing disabled.
- Persistent per-device installed-manifest metadata, enable toggle,
  refresh, reorder and removal with confirmation.
- Updates that request *new capabilities* are refused until a later
  explicit approval flow.
- No remote executable scripts, no addon endpoint requests, no playback
  routing, no account tokens, no imported libraries in this phase.
- A clearly labelled **offline demo addon** can be installed without network
  to test the UI and persistent enable/reorder/delete operations. It has no
  playable audio and cannot refresh its sample URL.
- Stremio `resources/types/catalogs` manifests are detected and rejected
  with a specific compatibility explanation, not a generic JSON failure.
  This includes Flix-Music (https://flix-music.vercel.app/manifest.json),
  which advertises Stremio `catalog/meta/stream` resources and a `movie`
  content type for its chart/list-based music catalogs. Apollo currently accepts
  only its own v1 declarative manifest format. Stremio compatibility needs
  a dedicated protocol adapter and a source/rights review; silently mapping
  Stremio endpoints to Apollo's schema would create unusable addons.

## Manifest fetch restrictions

- HTTPS manifest ending in /manifest.json; no embedded credentials, query
  or fragments. The existing manifest parser rejects numeric-IP hosts,
  local/internal names and encoded traversal.
- Ephemeral URLSession, no cookies, no response caching, no redirects,
  short timeouts, streamed response capped at 64 KiB, JSON validated.
- **This is not a complete defense against DNS rebinding or a hostile
  CNAME resolving to a LAN address.** Harden DNS-to-connection checks and
  strict IP/redirect handling before using arbitrary addon endpoints.
- Installed toggles currently configure the registry only. They do not
  imply that a remote stream has been tested or will play.

## Next: instant-ish addon audio, without Nuvio's movie-source delay

### Source routing

1. **YouTube default:** existing YouTube Music results, suggestions,
   library and streaming continue exactly as before.
2. **Independent music search:** opt-in addon catalogs get async search
   queries in parallel, with per-provider limits and independent results.
   For live performances not listed on YouTube Music, show standalone
   results tagged with the addon name and live-event description.
3. **Pre-resolve before Play:** after viewing an addon result, cache a
   trusted candidate (not a permanent signed media URL) while the user
   browses. During playback, prefetch one or two upcoming queue entries.
4. **On Play:** select a ready source immediately, otherwise resolve the
   chosen provider with a short time budget. Never wait for every addon
   to finish. First authorized playable result wins; slower providers
   may finish for a later user request. A configurable priority order
   and fast per-provider circuit breaker avoid repeat delays.
5. **Player:** pass the validated source's own audio/HLS URI and media
   metadata to MPV via PlaybackManager/PlayerController. Preserve
   source identity, cancellation, expiry, seeking limits and errors.
6. **Manual choice:** when versions differ, let the user select the
   recording/provider. Do not mistake a studio recording, radio edit,
   bootleg, preview or separate concert performance for an exact match.

### Suggested performance targets (NOT verified results)

- Cache manifest/endpoint capabilities on installation, not at playback.
- Prefetch at most 1–2 next tracks and a few visible external results.
- Parallel provider work bounded by device network/battery constraints.
- First viable provider target ~1 second on a warm connection, with an
  explicit shorter primary-provider budget. These are measurements to
  evaluate, not promises; cold start and slow upstream APIs vary.
- Cache query metadata with modest TTL, never reuse signed stream URLs
  past expiry and never log bearer tokens.

### Safety and compatibility

- Addon's own search result/provider ID is authoritative for playback;
  matching ID/ISRC/artist and duration supports cross-service discovery,
  not arbitrary substitution of YouTube audiovisual material.
- Validate audio stream URLs against allowed MIME types, HTTPS and
  authorized origins; do not trust a random user-controlled redirect.
- Live streams may have unknown duration and no seeking. Podcast/live
  progress and external tracking require their own logic.
- Do not bypass paywalls, DRM, geographical restrictions or copyright
  licensing to get a purportedly instant stream.
- Apple App Store Guideline 2.5.2 restricts remotely downloaded executable
  code that changes functionality. Keep addons declarative and runtime
  capabilities implemented in the shipped app.
- Before any external audio integration, review the relevant services'
  API terms; especially YouTube API restrictions on alteration, data
  aggregation and playback.

References:
- https://github.com/NuvioMedia/NuvioMobile
- https://developer.apple.com/app-store/review/guidelines/
- https://developers.google.com/youtube/terms/developer-policies

## Review / validation

- Core state checks: bash scripts/test-music-addon-manager.sh
- Existing foundational manifest checks: bash scripts/test-music-addons.sh
- iOS build and on-device UI QA are required; do not assume UX is
  verified from the standalone Foundation test alone.
- Keep this PR Draft. No merge until owner approves.
