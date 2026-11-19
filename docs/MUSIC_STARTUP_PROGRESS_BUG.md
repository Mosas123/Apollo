# Music startup progress / stale track intent — iPhone beta incident

## Evidence

The 2026-11-19 physical iPhone screen recording lasts ~3.66 seconds.
It shows the main player alternating repeatedly between **MONACO**
(4:27, Lossless, around 0:30 or 0:00) and **NADIE SABE** (6:11,
High, around 0:00–0:07). The artwork is from the same album.
This is **not merely a progress slider animation**: titles, total durations
and quality badges alternate. The video alone cannot prove whether both
audio sources switch; audio logs are still required for that distinction.

The earlier SponsorBlock tuning landed in Trop commit
`e2e6875d7fe1dda12d898767652d99836034e84f`: prefetched segments,
24-hour cache and 250 ms prefire. SponsorBlock itself only requests
`PlayerController.seek(to:)` and never selects the next track.

## Confirmed code defects

1. The **Skip intro at start** toggle was honored by the optional
   preloaded-start seek but **not** by the repeating `SponsorBlockIntegration.tick`
   loop. With the toggle off, a cached `music_offtopic` segment beginning
   near zero could still jump the playback bar as soon as the music started.
   We now enforce the opt-in and <=25-second cutoff consistently.
2. `NowPlaying.playCurrentSong` allowed a **superseded asynchronous resolver**
   to reset the active request's `isResolvingNext` flag and failure counter,
   and then call `handlePlaybackFailure`, potentially auto-skipping a
   different song. It now fences every late completion by **both**
   playbackGeneration and videoId, before changing flags or the queue.
3. `PlayerController.play` published source quality and track identity
   **before** awaiting the optional SponsorBlock preflight, then rechecked
   only the optional queue intent. We now stage mutations until the await
   returns and fence even non-queue loads using a monotonic load serial.

The defects in #2 and #3 are viable explanations for cross-track
flickering, but the attached video cannot prove which caller triggered
the original overlapping play requests. Preserve `PLAY_INTENT` logs
on reproduction to distinguish queue auto-advance from a rapid user action.

## Regression plan

Automated: `.github/workflows/playback-start-regressions.yml` compiles
the *actual pure policies* used by the app and executes 15 cases:
intro toggle on/off, 25-second limit, 250 ms prefire, ordinary mid-track
skips, invalid timestamps, stale track/epoch and ABA transitions.

Physical iPhone (opt-in Apolo music beta):
- Start MONACO, pause/resume and confirm the song title and quality stay
  stable; a disabled intro toggle must not seek to an intro's end
- Switch once to NADIE SABE and back; neither selection should bounce
  unprompted, and the duration must match the selected song
- Rapidly change A → B → A while lossless/high streams resolve to
  exercise the stale-intent guard
- Test an ordinary SponsorBlock segment away from the beginning to confirm
  non-music skipping still works
- Retest Dolby Atmos, Lossless, radio LIVE, manual seeking, remote controls,
  queue completion and MPV fallback

Do not claim the intermittent symptom fully resolved from static policy
tests or a successful IPA build; compare real-device playback plus logs.
No merge until hardware acceptance.
