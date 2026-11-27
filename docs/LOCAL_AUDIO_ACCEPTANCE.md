# Local audio in Apollo — offline playback beta

## Confirmed implementation gaps

The built-in download writer produces **M4A, MP3 and FLAC**. But
`DownloadManager.scanDownloadsSync` previously recognized only `m4a`;
MP3 or FLAC files without a current database row were not re-adopted into
Downloads after a restore, database rebuild or reinstall.

The existing Downloads tap route awaited `localURL(for:)` but never
carried the queue's playback generation to the player. A slow database
lookup could therefore activate a superseded local song.

Apolo previously pre-probed every local M4A/MP3/AAC using libavformat,
which could reject an otherwise Apple-compatible local asset before
native AVPlayer was attempted.

## Changes in this stack

- Import local audio using **Downloads → Import Audio**. Select files from
  iOS Files; Apollo copies supported audio files into its own Downloads
  folder under a unique `local:<UUID>` identity, stores a database row
  and closes any external security-scoped access. Files need not remain
  available in the original app, iCloud or file provider.
- Supported audio file extensions: M4A, M4B, MP3, AAC, MP4, FLAC,
  WAV, AIFF, CAF, Ogg/Opus, WebM audio and available FFmpeg codecs
  including APE/TTA/WV/WMA/MPC. Support varies by actual embedded codec.
- The local file scanner also recognizes those formats and existing
  download filenames, including imported `local:<UUID>` files. Deleting
  a track or clearing all Downloads also deletes the app's imported
  **copy**, not the original file from Files.
- A Downloads row captures its queue playbackGeneration before async
  local path resolution; obsolete lookups cannot start an old source.
- The source MIME hint follows the file's extension. Apolo uses the
  Apple native route for M4A/M4B/MP3/AAC/MP4 and existing FFmpeg
  route for FLAC/Ogg/Opus/exotic formats.
- The App Transport Security policy and network/music/radio decoders
  remain unchanged. No audio is converted during import.

## Acceptance on iPhone

1. Import an M4A, MP3 and FLAC from Files. Start one directly from
   Downloads. Verify audible sound, progression and pause/resume.
2. Test in **Airplane Mode**. No streaming fallback or network request
   should be required for a valid imported file.
3. Force-quit and reopen Apollo, visit Downloads and repeat playback.
   All three files must still appear.
4. Try next/previous and rapid song selection, then an imported track
   from a mixed queue. The old track must not take over late.
5. Compare audio quality and Dolby/Atmos on an existing online music
   source. Verify LIVE radio still plays with its indicator.
6. If a format does not play, preserve the codec, extension, file size,
   `APOLO_BETA`/fallback logs, and device crash report if present.
   Simulator CI alone does not prove physical playback.

This is a Draft beta. No merges or production installation implied.
