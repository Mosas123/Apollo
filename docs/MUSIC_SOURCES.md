# Music sources (work in progress)

Trop currently searches and plays YouTube Music via `SwiftyTube` and stores queue
entries as `SongItem.videoId`. Those IDs and YouTube-specific features **must not**
be reused for tracks from other providers.

## Phase 1: Audius catalogue foundation

`Trop/Core/MusicSources` introduces:

- `MusicCatalogID`, which scopes IDs by source (e.g. `audius:TRACK_ID`).
- `MusicCatalogTrack`, a separate representation of a search result.
- `MusicCatalogProvider`, a read-only search + stream-URL contract.
- `AudiusClient`, querying `GET https://api.audius.co/v1/tracks/search` and
  preparing `GET /v1/tracks/{id}/stream` for openly streamable tracks.

The client does not send login credentials or attempt to unlock premium/gated
tracks. It filters tracks with `is_streamable != true`, gated tracks, and
unavailable tracks. Actual HTTP playback can still fail due to regional
restrictions, removed content, rate limits, or unavailable stream servers.

**Not yet wired to the user interface, `PlaybackManager`, downloads, history,
likes, radio, lyrics or persistence.** This is intentional: existing YouTube
playback and queues remain unchanged in the first PR.

## Next integration phase

1. Introduce provider-aware identities and routing in the playback pipeline,
   including any queue serialization/migration needed to preserve old saves.
2. Ensure YouTube-only integrations (SponsorBlock, YouTube radio, Canvas,
   video-mode and YouTube-specific lookup) do not run on Audius tracks.
3. Add an Audius section/filter in search and handle cancellation and errors
   independently of YouTube search.
4. Confirm attribution, links, and licensing obligations for each provider.
5. Add Jamendo after its developer credentials and permitted use are verified.

## Validation

Run `bash scripts/test-audius-client.sh` on a machine with Swift 6 installed.
These deterministic checks cover Unicode query encoding, bounded search
limits, API response parsing, restricted-track filtering, source-scoped IDs,
stream URL construction, and HTTP error propagation. This does not substitute
for an iOS build, a real Audius API call, or full playback testing.

References: https://docs.audius.co/api/ and https://docs.audius.co/developers/guides/gate-release-access/


## Phase 2: Provider-aware playback routing (stacked draft)

Audius tracks can be adapted to `SongItem` for existing queue persistence,
using a synthetic `audius:<track id>` key. The playback manager detects these
keys and resolves Audius audio URLs without invoking YouTube stream resolution.
SponsorBlock and YouTube radio/autoplay requests are gated for Audius tracks.

Audius streaming is not yet exposed through search UI. The application must
not display a misleading YouTube video, YouTube share URL, or YouTube-only menu
action for an Audius item when the user interface is connected.

**Note:** Direct stream URLs may require redirects and may fail because of
region restrictions, app/platform network policies, or server availability.
No live stream playback has been tested yet. There is no download support for
Audius, and `resolve(forDownload:)` deliberately rejects that route.


## Phase 3: Audius search UI (stacked draft)

YouTube and Audius searches run in parallel, with failures isolated so one
source can still return results. Audius has its own searchable filter and
separate song rows that feed the source-prefixed queue. The UI deliberately
does not offer YouTube song navigation, radio, or downloads for those rows.

This is the first user-visible integration. Real iPhone playback and
full-system regression tests remain required before any merge.
