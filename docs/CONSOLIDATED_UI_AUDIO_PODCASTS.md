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


## Follow-up #8 — Atmos-only queue transition (reported on iPhone)

**Report:** When a Dolby Atmos track follows another track in the queue, it
sometimes does not start automatically, or starts after a noticeably longer
silent pause. The user suspects this is specific to Atmos. Treat as a new,
unresolved **subset of #6 (track-to-track gap)**, not a proven Dolby decoder
failure or a confirmed missing autoplay event. No device timestamps yet.

### Code-path audit

- `PlaybackManager.prefetchUpcomingUpgrades` prefetches the **resolved signed
  URL/PlaybackResult**, including the Atmos add-on result, but Thrum does not
  yet feed `ApoloEngine.enqueueNext`; it is not a decoded/ready AVPlayerItem.
- On EOF, `NowPlaying.stopped` calls `playNext(automatic: true)`, which starts
  a fresh resolve/load rather than using an engine-level queued item.
- `PlayerController.playWithApolo` explicitly stops the old Apolo backend,
  calls the new `load`, and only then calls `play()`.
- In Apolo's `AVPlayerHost.load(track:)`, the old AVQueuePlayer items are reset
  and `AVAsset.loadTracks(withMediaType: .audio)` is awaited **before**
  inserting and starting the new player item. Dolby/E-AC3 is intentionally
  routed through native AVFoundation without a processing tap. Additional
  codec/asset/route preparation time is a credible explanation for a longer
  gap, not yet measured.
- Apolo supports `enqueueNext` and AVQueuePlayer already, but Thrum must
  synchronize its own queue identity/state with Apolo auto-advance before
  enabling it, particularly for mixed Atmos → AAC/FLAC and vice versa.

### Investigation / reproduction matrix

Compare automatic transitions (not manual Next):
1. AAC → AAC and FLAC → FLAC (baseline).
2. AAC → Atmos, FLAC → Atmos and Atmos → Atmos.
3. Atmos → AAC and Atmos → FLAC.
4. Repeat with a prefetched/cached Atmos result and with a cold result.
5. Repeat with `upgradeDuringPlayback` off/on, Wi-Fi/cellular, Bluetooth
   AirPods and built-in iPhone speaker.
6. Confirm whether the UI changes song and shows pause/playing while the
   audio is silent, or whether the queue itself waits.
7. Capture redacted `TRANSITION`, `APOLO_BETA begin/loadReturned/firstPlaying`,
   `PLAY_INTENT`, and prefetch logs. Measure milliseconds from EOF to
   source load, first playing, and first audible sample. Preserve the MIME
   and `isAtmos` signal, never signed URLs/authorization headers.

**Provisional diagnosis:** a prefetched stream URL is not a pre-buffered
Dolby decoder/AVPlayerItem. No codec-specific crash or failure has been
established. Implementation needs a single-owner queue handoff and
verified spatial-audio route readiness. Do not disable Atmos or bypass
native AVFoundation as a quick workaround. No code changes were made for
this issue at the time of logging.


## Bug #9 — Instagram interruption triggers premature MPVKit fallback (FIXED IN CODE, NEEDS DEVICE TEST)

**Reproduction:** With *Raindrops (Insane)* playing under Apolo, Instagram pauses
music. Without reopening Thrum, after Instagram's audio session eventually
releases ownership, the song resumes under **MPVKit instead of Apolo**.

Evidence from uploaded `log(2).txt`, 19 Nov 2026:
- 12:03:13.614 Apolo `firstPlaying` for Raindrops.
- 12:03:52.155 `AUDIO_INTERRUPTION began`.
- 12:04:32.835 `AUDIO_INTERRUPTION ended` (40.680 seconds of iOS interruption).
- 12:04:33.146 `APOLO_BETA loading timeout; using mpv fallback` and
  `APOLO_BETA switching back to mpv` (only **311 ms** later).
- 12:04:33.347 MPVKit `TRANSITION FILE_LOADED`, same track.
There was no logged Apolo decoder error. Prior *Superhero* case showed the
same post-interruption premature watchdog behavior.

**Root cause in Thrum:** `monitorApolo` used `Date().timeIntervalSince(begun)`
to enforce a 20-second `.loading`/`.idle` timeout even after Apolo had
already reached `.playing`. A transient recovery state after >20 seconds
of ordinary playback or a long iOS interruption therefore immediately
triggered MPVKit fallback. The original code had no independent
post-interruption recovery deadline.

**Change in this PR:**
- Add `ApoloFiniteAudioWatchdog`, which measures a *continuous*
  `.loading`/`.idle` phase for **finite** audio. It resets on `.playing`
  and `.paused`, keeps the deadline across idle ↔ loading, and
  excludes time during a system audio interruption.
- Store the time of `AVAudioSession.interruptionNotification` **ended**
  so the deadline still resets if iOS suspends the app and it never polls
  the watchdog during the interruption itself.
- Preserve the 20-second real-stall fallback and the existing separate
  bounded live-radio reconnect policy.
- CI `ApoloInterruptionWatchdogChecks` tests cold-load stalls, a long
  Instagram-like interruption, 311-ms recovery check, suspended polling,
  continuous idle/loading stalls, and pause/play phase resets.

**Remaining question:** iOS owns the exact duration of Instagram's
interruption. The log proves the interruption lasted ~40.7 seconds but
cannot tell when the user physically left Instagram. This fix removes
Thrum's *incorrect* forced engine switch; it does not guarantee that
Instagram relinquishes the audio session within 15 seconds.

**Acceptance:** With Apolo music beta on and the engine indicator visible,
play a track for >30 seconds, open Instagram with audio enabled, return
without reopening Thrum, and verify it resumes via **Apolo**, not MPVKit.
Repeat with short and long interruptions, background/suspended application,
paused-before-interruption, lockscreen and AirPods. Deliberately simulate
a genuine >20-second pending audio state to confirm MPVKit fallback remains.
