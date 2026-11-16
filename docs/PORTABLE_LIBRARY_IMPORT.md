# Import music libraries and playlists from a file — Phase 1

This is a **read-only CSV foundation** stacked on the Google library merge
planner PR. It does not yet offer a Files picker or write anything to the
database. User activation/approval, transactional persistence and rollback
are separate later phases. No remote audio is downloaded.

## Supported in this phase

- **Soundiiz CSV** playlist/favorite-song exports:
  title, artist, album, ISRC, platform, trackId (extra columns ignored)
- **Spotify Exportify-style CSV** playlist exports:
  Track URI, Track Name, Artist Name(s), Album Name, ISRC.
- Generic UTF-8 CSV/TSV/semicolon-separated track lists with a title column.
- Quoted separators, double-quoted text, embedded line breaks, Unicode
  names, optional UTF-8 BOM and CRLF line endings.
- Repeated playlist occurrences and original row ordering stay intact;
  LibraryImportPlanner deduplicates library identities separately.

## Key safety details

- Reads only selected file bytes; no third-party upload, network or API
  access. Rejects malformed CSV, missing titles, files over 8 MiB, over
  25,000 rows, overly long fields or headers, and invalid UTF-8.
- The user-selected Trop profile ID is required. Neither the file name nor
  the CSV is trusted to identify a logged-in Google/Spotify account.
- Verified provider + track IDs and ISRCs can help merge identities.
- When no trustworthy ID is present, source identity is scoped to the
  exact file content hash and row position. Re-importing the same file is
  idempotent; newer/different exports are **not automatically conflated**
  based only on matching titles. A later UI will surface uncertain matches.
- Original playlist order is stored separately from canonical library
  matching, so repeating the same song intentionally in a playlist doesn't
  create duplicated canonical tracks.
- Source metadata (including platform column) is **not authorization**:
  Spotify/Qobuz/etc playback still requires a supported, lawful provider.
- Nothing deletes existing local files, imported items, subscribed podcasts,
  playback progress, liked songs, or user changes.

## Future import formats

- Spotify's official data export (Your Library, playlists, streaming
  history): JSON, with a format-specific adapter and test fixtures.
- Google Takeout/YouTube Music: CSV, JSON and relevant playlists/history
  using verified schema versions.
- Apple Music exported library / playlists: XML.
- Soundiiz JSON/XML; XSPF; M3U/M3U8; and podcast OPML where applicable.
- Direct account connections (OAuth when provided), optional after manual
  import is proven stable.

## Future user flow

Settings → Library → Import from File → iOS Files picker → parse locally →
preview new/already-present/review-needed items → user selects categories →
atomic save / rollback → check unified library.

Do not send imported tracks back to Spotify/Google or replay historical
Last.fm scrobbles. User data imports require consent and transparent
data-retention controls.

Sources:
- https://support.soundiiz.com/hc/en-us/articles/38063068900754-How-to-Export-Your-Playlists-and-Favorites-to-a-File
- https://github.com/watsonbox/exportify
- https://support.spotify.com/us/article/understanding-your-data/
- https://support.google.com/accounts/answer/3024190
- https://support.apple.com/en-vn/guide/music/mus27cd5060f/mac

Run tests: bash scripts/test-portable-library-csv.sh (Swift 6, CryptoKit).
All fixtures are synthetic; no real credentials or library files are used.

**Draft only: no merges before review and on-device testing.**
