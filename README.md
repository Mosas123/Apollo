# Apollo

A free and open source music and podcast player for iOS.

## Import playlists

Settings → Integrations → **Import playlist** accepts CSV files from [Exportify](https://exportify.app) (Spotify) or any export with song title and artist columns. Apollo creates a local playlist and matches each row against its catalogue; nothing is uploaded.

For Apple Music or YouTube Music, move the playlist to Spotify with a free transfer service first, then export it with Exportify.

## Features

- No ads
- SponsorBlock: skips sponsor reads, intros, outros and non-music sections (silence, talking)
- Spotify-powered catalogue for songs, albums, artists and playlists
- Synced lyrics (Musixmatch, Netease, Kugou, LRCLIB, Genius)
- Library sync (playlists, albums, artists, podcasts)
- Live radio (opt-in beta): native HLS/HTTP and ICY, reconnect handling and broadcaster metadata
- Apolo audio engine (opt-in beta): native and FFmpeg routes, EQ, limiter, ReplayGain and Spatial Audio
- Local library import, downloads and podcast playback
- Equalizer
- Custom app icons and themes
- Queue management and listening history

## Live radio and audio engine

Live radio is behind an explicit beta toggle; default installs keep the existing
player and MPV fallback. The radio path supports native HLS/HTTP playback, ICY
metadata, station switching, bounded reconnects and a stall watchdog.

Radio titles and artwork come from ICY or broadcaster APIs.

The Apolo engine is also opt-in. It keeps Apple-native playback for compatible
formats, uses FFmpeg for exotic codecs, and preserves EQ, limiter, ReplayGain,
Spatial Audio and Atmos where the route supports them. MPV remains available as
fallback.

## Recent improvements

- Live radio: HLS/HTTP/ICY routing, reconnect budget, stale-callback fences,
  duplicate-request suppression, 35/40-second stall watchdog and recovery logs.
- Audio: Apolo audio-only beta, local sandbox routing, studio-audio matching,
  interruption recovery and safer playback-start behavior.
- Library: local import/reconciliation, download visibility and podcast support.
- Playback: SponsorBlock intent guards, queue/history fixes and artwork lookup.
- CI: integration checks, SwiftLint cleanup and unsigned iPhone IPA builds.

## Installation

Requires iOS 26.2 or later. No account is required for the catalogue.

### Feather / AltStore / SideStore

Add the Apollo source, then install the latest stable release (unsigned - your client re-signs it with your Apple ID):

```
https://raw.githubusercontent.com/Mosas123/Apollo/main/altstore.json
```


> **Note:** AltStore PAL is not supported.

Stable releases are available from the [releases page](../../releases). Nightly builds are available in the[Actions](../../actions) tab.

### Manual Installation

 To build an unsigned IPA locally, run `./build_ipa.sh`; the output is `build/Apollo.ipa`.

## Notable mentions

- [InnerTubeX](https://github.com/MetrolistGroup/innertubex) - eXtended InnerTube API library for Kotlin
- [zemer-cipher](https://github.com/ZemerTeam/zemer-cipher) - YouTube cipher deobfuscation and PoToken generation
- [Metrolist](https://github.com/MetrolistGroup/Metrolist) - YouTube Music client for Android

## Community



## License

The code is licensed under [GPL-3.0](LICENSE.txt). Third-party components and their licenses are listed in [NOTICE](NOTICE).

The Apollo name, icon and cl0udly branding are separate from the code license and are not granted by it. Forks must rebrand before distributing; see [TRADEMARK.md](TRADEMARK.md). Official builds are published only from this repository.

Apollo is not affiliated with, endorsed, or sponsored by Google or YouTube.
