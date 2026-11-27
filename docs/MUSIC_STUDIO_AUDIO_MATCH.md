# Music song vs music-video audio matching — beta

## Reported symptom

While playing a song such as Bad Bunny's "Moscow Mule", Apollo may
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
   artist, exact release and bounded duration validation** (20 seconds
   without release proof or 60 seconds when the album matches, allowing
   video-only introductions). Never substitute a cover,
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

## Second iPhone finding: NUEVAYoL (2026-11-19)

The latest album-audio matcher fixed the reported "Moscow Mule" example,
but the same tester heard the music-video audio of **NUEVAYoL** while the
full player displayed about **3:42**. The album recording is approximately
**3:03** (independent published catalog duration). This gives a specific
39-second duration difference compatible with the video's extra narrative.

The original matcher had **three blind spots**:

1. It treated `SongItem.isVideo` (a characteristic of the *source ID*)
   as proof the user explicitly **chose to play a video**. That suppressed
   matching when an OMV was mistakenly present in the Songs listing.
2. Only positively known `MUSIC_VIDEO_TYPE_OMV/UGC` sources triggered
   matching. Album rows missing this upstream flag could slip through.
3. A 39-second duration difference was rejected without a confirmed
   album identity, even when the original source was known to be a video.

### Revised behavior

- `SongItem.recordingPreference` is a backwards-compatible optional
  media-intent field. Search Songs taps record `.albumAudio` and
  explicit Videos taps record `.musicVideo`. The original row's
  `musicVideoType` / `isVideo` remains source metadata, not intent.
  Album and older queue entries default to music-first.
- A source marked as a video, or an *untyped source* of a known album,
  initiates an optional search for a verified YouTube Music ATV art-track.
  A confirmed ATV source is never rematched.
- For a positively video-typed source, an **up-to-60-second** intro/outro
  difference is allowed when the candidate itself is ATV and title /
  artist identity is exact. An unverified source still needs a closer
  duration match or verified album.
- Duplicate ATV results are deduplicated. Distinct releases without an
  original album identity are considered ambiguous and rejected.
- If no reliable ATV exists, the stream is not silently relabeled as
  studio audio; the resolver logs a `MUSIC_MATCH no verified ATV source`
  diagnostic. The existing video-audio fallback may still play and must
  not be interpreted as a verified studio match.

### Hardware acceptance

Re-test **NUEVAYoL** from **Songs** (expect album audio close to 3:03)
and from **Videos** (expect the intentionally selected music video).
Then retest **Moscow Mule**, a live/remix track, older saved songs,
an unknown-type album entry, SponsorBlock, radio, local audio and Atmos.
Capture `MUSIC_MATCH` logs if either track is still wrong.

This is a beta regression fix, not evidence of perfect catalog matching.
