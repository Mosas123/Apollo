# Thrum beta: UI/audio stabilization + independent Apolo Podcasts

**Status:** Draft, requires GitHub Actions and physical-iPhone acceptance.
**Base:** stacked on PR #16. We manually integrated the two files from
`main` commit `bb4e00a8` (FFmpeg session-token ownership and duration-cache
cleanup) before continuing. Never overwrite these with a previous branch.
The consolidation is one Thrum PR; the main branch is unchanged.

## User-reported regressions and scope

| # | Reported problem | Implemented here | Verification |
|---|---|---|---|
| 1 | Queue button's overlaid Repeat accidentally toggled | Remove overlay; Repeat remains in QueueView | iPhone tap Queue on all layouts |
| 2 | Last.fm API error 10, then blank auth sheet | Persistent inline failure and build-credential message; remove dismissible blanking alert | Invalid key and valid-key login required; **real credential is not available in repo** |
| 3 | Lyrics screen empty when no provider | Loading / unavailable / failed states and retry; preserve layout | No lyrics, offline error, successful lyrics |
| 4 | Atmos selected, download tries an E-AC3 source as FLAC | Audio download preference ignores Atmos playback toggle; require true Lossless + FLAC codec for FLAC muxer | Download while Atmos playback preference is on: FLAC/AAC, not mislabeled Atmos |
| 5 | Niagara Falls vocal resolved from Instrumentals album | Version-sensitive title/album matching and cache keys, plus unnormalized album edition comparisons in ATV matcher | Vocal vs instrumental both directions, same-duration, missing metadata |
| 6 | Tiny silence at track boundary despite metadata prefetch | **Still open**. Current prefetch warms URLs and metadata, not a queued decoded source in Apolo. Do not falsely claim gapless | Needs Apolo/Thrum queue ownership design and iPhone waveform/timestamps |
| 7 | Quick Picks / album cover replaced twice by wrong cover | Keep selected artwork as trusted source, resize same URL rather than substituting a cross-catalogue or video cover | Raindrops (Insane), Volver a Nacer, album switch, lockscreen |
| P | Podcasts need independent Apolo route | Music / Podcast / Live Radio switches; podcast finite audio bypasses music add-ons and ATV matching; resume tied to generation and actual source load | Streamed and downloaded episode, resume, 15/30s seek, AirPods, background, fallback |

## Source matching quality

`TextMatch.normalizeTitle` strips bracketed phrases as a useful **search
normalization**, but no longer controls whether vocal and instrumental editions
are equivalent. `TextMatch.versionMarkers` runs **before** that normalization,
and filters instrumental(s), karaoke, live, remix, cover, demo, etc. The
`AddonSourceResolver` source/album cache keys and `MetadataResolver` cache
also retain full album-release identity. ATV replacement checks the raw
edition label before normalizing. Missing album proof must never be invented.

These changes do not solve all record-identity problems: an instrumental
source may have completely mislabeled metadata and no matching qualifiers.
Log metadata/album/stream identity for further analysis.

## Dolby Atmos vs downloads

An E-AC3 Atmos bitstream is compressed and **not** lossless FLAC. The
playback Atmos preference remains untouched. Offline lossless resolution
asks add-ons for actual FLAC instead; if none is found, normal audio
download fallback can be used, rather than trying to remux E-AC3 as FLAC.

Do not add an Atmos badge to an AAC or FLAC file just because playback
preferences have Atmos enabled. If true offline Atmos becomes a
requirement, it needs its own supported container/capability negotiation,
without reusing the FLAC metadata/remux path.

## Podcasts

Podcast media are **finite** and seekable, unlike indefinite internet
radio. Their playback engine toggle is independent. On existing installs,
the new podcast toggle inherits the old music-beta setting once, to
preserve the previous de-facto behavior until the user chooses otherwise.

Podcast episodes do not enter music add-on lossless matching, Spotify-style
quality hot-swap, album-audio video matching, or SponsorBlock startup seek.
On episode selection, a saved resume position is attached to the active
playback generation and consumed during PlayerController's source load;
the previous loop waiting for `currentVideoId` incorrectly assumed ID
publication meant the audio was ready.

MPVKit remains the fallback. Thrum still owns AVAudioSession,
MPRemoteCommandCenter, queue, and lockscreen metadata.

## Not safely solvable in a cosmetic PR

**True gapless (#6):** Apolo's `enqueueNext` and AVQueuePlayer exist,
but Thrum's metadata/stream prefetch does not call them. Enqueueing now
without Thrum detecting Apolo's internal auto-advance would leave the UI
on the old track and risk a duplicate reload. The FFmpeg route currently
opens the next decoder at the previous track's end. A release-quality
implementation needs:
1. a prepared source object bound to `videoId` and source generation;
2. preload the next decoded audio (not just URL), with memory/time bounds;
3. a single handoff event that advances both Apolo and Thrum queues;
4. cancellation on manual skip, shuffle, source expiry, quality changes;
5. tests for AVPlayer-to-AVPlayer, FFmpeg-to-FFmpeg and mixed format routes.
Do not claim this is fixed merely because `gaplessPlayback` is true.

**Last.fm (#2):** error code 10 comes from the server rejecting the
app's supplied API key. This PR prevents blank UI and gives the actual
developer action needed, but does **not** create or replace a valid
Last.fm key. Release and nightly workflows read configured secrets.
A functional login requires valid secrets and a real on-device login.

## Acceptance gates

- CI: the existing Xcode IPA workflow, SwiftLint, SponsorBlock/policy,
  recording/FLAC and previous music-add-on regressions must pass.
- Verify the reported songs: Niagara Falls vocal vs instrumental;
  Moscow Mule, NUEVAYoL, Raindrops and Volver a Nacer.
- Listen through at least 10 continuous track transitions and
  measure actual audio gaps. Don't mark #6 closed from this PR.
- Test Last.fm with valid and invalid key in a non-production build.
- Test empty Lyrics with Wi-Fi off/on and a successful provider.
- Download FLAC while Atmos preference is on, airplane-mode playback.
- Podcasts: both switches on/off, 60+ minute source, resume position,
  next/previous, 15/30s seek, background, AirPods and MPVKit fallback.
- Retest Dolby Atmos, Lossless, radio LIVE and reconnect, local imports.
- Do not merge until device checks are signed off by the user.
