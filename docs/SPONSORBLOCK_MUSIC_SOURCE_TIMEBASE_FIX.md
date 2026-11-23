# SponsorBlock segment timestamps must match the actual audio source

## Root cause candidate (strongly supported; confirm by on-device A/B)

Trop historically uses a raw YouTube `videoId` for the entire album
queue, including when its resolver selects a different studio master
from an addon. SponsorBlockIntegration.tick previously checked only:
- `NowPlaying.playbackKind == .music`
- the original videoId equal to the result videoId
- the result streamUrl equal to NowPlaying.currentStreamURL

This does **not** prove the stream's timestamp space is the original
YouTube video. The addon result intentionally preserves the videoId as
the **queue identity** and uses `clientName="addon"`, so it passed
those checks. A video `music_offtopic` segment then called
`PlayerController.seek(to: segment.end)` on *another recording*.

## iPhone evidence (21 November NY, kept private)

- Original Atmos-labelled addon audio, native AVPlayer route:
  `renderer.nativeClock` at pos=161.750s, rate=1.0, then
  `kind=jump pos=183.712 maxJump=21.501 jumps=1`; actual native EOF
  followed. No manual Next was logged.
- Same album song selected with Lossless quality: actual
  `container=flac codec=flac duration=183.685` and therefore the
  libavcodec/AVSampleBufferAudioRenderer route, not native AVPlayer.
  It logged `renderer.seek target=186.641` at 22:48:41.169, beyond
  the FLAC duration; immediately `renderer.decoderEOF`, automatic
  queue advance and `listened=163.5s`.
- The exact ~186.641 target, absence of a manual/remote seek in logs,
  and SponsorBlock's unchecked video-based skip end are a **strong
  common-mechanism hypothesis**. We did **not** retrieve or archive
  the specific server segment response (do not claim independently
  verified SponsorBlock segment boundaries).
- The first `renderer.seek target=0.000` at 22:45:58.377 is a
  separate seek and does not explain the terminal end skip.

## Minimal safe fix

- `SponsorBlockSkipPolicy.allowsSource(clientName:)`: **positive**
  allowlist of the known SwiftyTube YouTubeClient identifiers
  (WEB, WEB_REMIX, IOS, ANDROID, ANDROID_VR, TVHTML5,
  TVHTML5_SIMPLY_EMBEDDED_PLAYER, VISIONOS).
- All external/unknown providers, including addon, Qobuz, JioSaavn,
  Audius and local, **fail closed**. This prevents any future source
  with a copied YouTube videoId from triggering a video-timeline skip.
- Gate SponsorBlockIntegration.tick on current resolved clientName,
  same ID, and exactly the active URL. A music video transition or
  expired current result cannot bypass it.
- Bypass optional SponsorBlock intro offsets for external / unknown
  sources in PlaybackManager.playNetworkResult; no regressions of
  explicitly opted-in true YouTube playback.
- Emit sanitized `musicOfftopic seek source=YouTube` telemetry **only**
  when an actual SponsorBlock video-timeline skip happens.
- No changes to FFmpeg, AVPlayer's clocks, audio decoded samples,
  queue EOF handling, the user library or iCloud.

## iPhone acceptance

1. Install an experimental IPA from this branch or a QA branch
   stacked on the existing [clock-audit IPA PR #59](https://github.com/Mosas123/Trop/pull/59).
2. Select album **DeBÍ TiRAR MáS FOToS > NUEVAYoL** with the default
   SponsorBlock setting **enabled**. Play with addon Lossless (CD)
   selected; do not seek or tap Next. The complete audio should run
   for approximately 183.685s and no `renderer.seek target=186.641`
   or early EOF should occur.
3. Repeat with the Atmos-labelled addon source; nativeClock should
   remain near 1x and reach true EOF without a ~21s `kind=jump`.
4. Check local queue and Now Playing change tracks only at genuine
   completion. Existing unrelated Now Playing stale-duration bug is
   not fixed by this PR.
5. Test a **real YouTube video audio** source only if authorized:
   SponsorBlock's deliberately enabled non-music skip should retain
   existing behavior when IDs and stream URL match.
6. Regression: new track switching, radio, podcast, local files,
   background/foreground and source upgrades; no credentials in logs.

### Temporary A/B without a new IPA

In settings disable SponsorBlock **Skip Segments**, restart the song
from zero, and repeat the same add-on FLAC/Atmos test. If the jump
disappears, that independently supports this diagnosis. Do not
presume confirmed before that test.

## Caveats

- The server-side SponsorBlock skip segment for this specific video
  could change, and its response was not captured in the private logs.
- The log does **not** itself attribute the unlogged call to
  SponsorBlock: an alternative app or system seek may produce the
  same renderer.seek line. The code path and timing make SponsorBlock
  the strongest candidate, pending on-device proof.
- Existing YouTube identity and tracking calls are being removed in
  separate migration PRs; this guards playback in the meantime.
