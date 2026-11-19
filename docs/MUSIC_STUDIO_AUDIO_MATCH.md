# Music song vs music-video audio matching — beta

## Reported symptom

While playing a song such as Bad Bunny's "Moscow Mule", Thrum may
use the audio from the related music video rather than the album's
standalone recording. This is a source/recording identity problem, **not**
evidence that Apolo is decoding a video file incorrectly. The example
has not been reproduced with a device resolver trace; exact affected
video IDs and whether multiple recordings exist remain to be confirmed.

## Code defects found

- `SongItem.isMusicVideo` recognized videos only when the subtitle
  began with the literal English word "Video". It **ignored** the
  already-parsed YouTube Music watch endpoint's `musicVideoType`.
  Official music video (`MUSIC_VIDEO_TYPE_OMV`) and UGC video
  (`MUSIC_VIDEO_TYPE_UGC`) results could be shown as ordinary Songs.
- The search parser trusted a shelf's "Songs" header even when the
  returned row itself had a video type, mixing audiovisual entries
  into song listings.
- `PlaybackManager` resolved the **original video ID**, so asking
  for audio-only streams still gave the audio mix from that video.
  Codec/bitrate selection cannot change a music video's recording.

## Beta fix

1. Classify search cards using the authoritative watch endpoint type.
   Keep OMV/UGC videos in Videos and ATV art tracks in Songs.
2. For legacy or ambiguous **song** entries whose resolved YouTube
   stream is positively typed as video, search YouTube Music for an
   ATV album audio recording with **strict recording title, credited
   artist and duration/album validation**. Never substitute a cover,
   remix, live version or an unverified type. Unknown metadata and
   explicit user-selected videos do not trigger rematching.
3. When an ATV match is found, the actual audio comes from its own
   stream URL. The visible queue metadata/history and video-mode
   identity stay tied to the original selected track, while the
   now-playing source descriptor reflects the real playing stream.
4. SponsorBlock intro and periodic skips do not apply to the original
   video's timeline after switching to an ATV recording.
5. A small positive/negative cache bounds repeated metadata searches.
   Failed searches do not block playback; the original audio remains
   the fallback rather than picking an unverified recording.

## Acceptance on iPhone

- Choose Bad Bunny's "Moscow Mule" under **Songs** and compare
  what is heard with the album version; do not infer it from cover art.
- Search **Videos** and explicitly open the official music video:
  video playback should retain its own recording.
- Try titles that have both an official music video and a separate
  official audio/ATV; verify the Music source match log shows original
  and audio IDs only when a validated rematch occurs.
- Test tracks marked live/remix/cover and tracks with missing artist
  credits; no false studio audio substitutions.
- Re-test normal YouTube songs, FLAC/Atmos upgrade, SponsorBlock
  mid-track skips, rapid song switching, local Files playback and LIVE radio.
- Reproduce with a device log to confirm the true source and any
  remaining mismatch. A successful policy test or IPA build is
  insufficient to certify exact content matching.

Draft, stacked on PR #14; no main merge or release.
