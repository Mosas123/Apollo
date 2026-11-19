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
