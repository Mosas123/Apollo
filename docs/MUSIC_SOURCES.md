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
