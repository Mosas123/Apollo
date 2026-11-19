# Thrum Beta 0.1 — audio-only Apolo integration

## Scope

The first beta tests ApoloEngine for **music playback only**. It does not add or migrate video rendering, video-only URLs, DASH/EDL pairing, radio or downloads. Thrum keeps ownership of queue, metadata, remote commands, the shared audio session and app lifecycle.

## PR 1 — Link smoke test (this draft)

- Add the ApoloEngine Swift package pinned to a specific revision from its embedding PR.
- Add a small `ApoloAudioBackend` wrapper with the embedding ownership flags disabled.
- Do **not** instantiate this backend from the app or change the active MPVKit playback path yet.
- Use the pull-request macOS CI to catch SwiftPM, simulator/device framework, linker, FFmpegKit and MPVKit coexistence issues.

## Subsequent PRs

1. Merge/validate ApoloEngine's embedding API and update this dependency to the merged commit or a tagged release.
2. Add a single music-only playback router with a debug toggle defaulting to MPVKit; make it the only writer of the audio session and remote commands.
3. Feed Apolo's current time, duration, playback state and errors into `NowPlaying`, and preserve the existing queue, artwork, lyrics, Last.fm and history.
4. Route downloaded audio and authorized direct MP3/AAC/FLAC URLs into Apolo; keep mpv fallback for incompatible/live sources; do not enable video playback in the beta mode.
5. Port or disable features that depend on mpv's ten-band `firequalizer`, SponsorBlock seeking, and mid-track quality switches until verified.
6. Validate screen lock, background playback, pause/seek/skip races, memory over long sessions, audio output changes and offline/online recovery on a physical iPhone.

## Exit criteria

Build + link succeeds, audio-only routing works with one owner of system controls, music playback survives background/lock, and no critical regressions in current Thrum features. This PR **alone is not a runnable Apolo beta**: it is the safe package-integration checkpoint.

## PR 2 — Real playback (stacked draft)

- Turn on **Player → Experimental Playback → ApoloEngine Beta (Music Only)**. The preference applies to the next song.
- `PlayerController` sends music URLs to ApoloEngine, stops mpv before starting Apolo, and keeps Thrum in charge of queue, metadata, screen-lock commands, history and UI.
- Pause, resume, seek, volume, elapsed time, duration and automatic next song are routed through the active audio engine.
- Playback errors and a 20-second stalled-loading watchdog trigger mpv fallback; old async operations use a generation check.
- Video mode is disabled while the beta toggle is on. Radio/podcasts stay on mpv for now. Downloads are unchanged.
- Apolo's five-band EQ is **not** equivalent to Thrum's ten-band presets, and EQ is intentionally not migrated in this beta.

### Manual acceptance check (required on iPhone)

1. Toggle OFF: old mpv path still works, including existing audio and video.
2. Toggle ON and select a playable music track: console logs `APOLO_BETA active audio only`, audible audio, artwork and progress.
3. Test pause, seek, next, lock-screen controls, AirPods, background and interruption behavior.
4. Test local file, MP3/AAC/FLAC from authorized direct URLs and a failing URL to verify mpv fallback.
5. Check 30+ skips, playing for 1–2 hours, memory growth and background battery. Do not release to others before real-device verification.

### CI caveat

Trop's SwiftLint job reports pre-existing serious violations in other files; review the diff separately and avoid weakening lint globally. The iOS IPA build is the first compilation gate; success is not a guarantee of runtime playback.


## IPA experiment — Live Radio (PR 3, opt-in)

This stacked draft integrates the already-tested `ApoloEngine` live radio
transport in Thrum, pinned to `067ebd150d94d4120327214752e0b22c17684b03`
(Apolo v7, simulator CI: 100 tests passing). Radio no longer uses the
finite-music `load` API: the app's adapter calls `loadLive`.

### Enable and observe

1. Open **Settings → Player → Experimental Playback**.
2. Enable **ApoloEngine Beta (Live Radio)** (independent of the existing
   music-only beta). The setting defaults OFF and applies to the next station.
3. In **Radio**, choose an HTTPS MP3/AAC station; the full player should
   display **APOLOENGINE (RADIO BETA)** while Apolo is active.
4. Try HLS (.m3u8), Ogg/Opus and FLAC streams, plus M3U/PLS station
   playlists. Check actual audio, start latency, metadata title updates and
   proper handling of stations with unknown duration.
5. Test station switching, pause/resume, headset interruption, lock screen,
   background, AirPods/AirPlay, and a Wi-Fi/cellular handover.
6. Simulate a broken stream. Apolo handles its bounded retry budget; the app
   allows a limited reconnection grace period before switching to
   **MPVKit (Fallback)**. The app must not skip the music queue on radio EOF.
7. Toggle radio beta OFF and select a new station: it must use MPVKit, even
   when music beta remains ON. Music, Lossless, Dolby and video are unchanged.

### Important test limitations

- Radio Browser exposes a codec hint and a URL; it does **not** identify
  every server's MIME type or know whether MP3 stations use legacy raw ICY.
  Opaque streams or playlists whose resolved URL has no format hint may
  require the MPV fallback, especially Ogg/Opus without an extension.
- Plain `http://` stations may be rejected by iOS App Transport Security for
  URLSession requests. **No global ATS exception is introduced in this PR.**
  Test HTTPS stations first; HTTP/legacy ICY device acceptance is a separate
  explicit security decision, not a reason to silently relax all app traffic.
- The Apolo/MPVKit fallback is one-way per selection; no automatic switch
  back to Apolo until a new station is selected.
- iOS CI produces an **unsigned** `Trop.ipa` artifact, not an already
  provisioned or App Store-signed build. Sideloading requires signing it
  with the user's own chosen installation tool.
- Simulator compile and unit tests are not proof of real-device memory,
  background, networking, or Dolby output. Use Instruments to check
  allocations across repeated station changes and 1–2 hour playback.

### Build route

The existing GitHub Actions **Nightly Build** workflow runs on pull requests
and executes `build_ipa.sh`, uploading `Trop-iOS` with `Trop.ipa` if
the device build succeeds. No main/nightly release is modified by this draft.
