# YouTube dependency exit — source audit (21 Nov 2026 NY)

**Status: RESEARCH / not activated.** Reviewed actual files in Trop/main. Do not delete SwiftyTube or rewrite user data yet.

## Goal

Trop owns music/podcast identity and user library. YouTube can only be a legally authorized optional playback source. No account requirement, YouTube-linked favorites/history/catalogue authority, or conversion of studio recordings into video audio. iCloud Private Database will carry **metadata only** (saved songs, albums, artists, ordered playlists, podcasts, episodes, and optional progress). **Never upload FLAC/MP3/M4A files, device paths, signed streams, cookies or keys.**

Important distribution gate: YouTube's official API rules restrict separating audio/video, downloads and background players. A raw YouTube audio-only resolver is not automatically permitted for released applications. See https://developers.google.com/youtube/terms/developer-policies .

## Verified code-level dependency inventory

| Area | Active dependency (Trop/main) | Required replacement |
| --- | --- | --- |
| Search | SearchService.swift lines 20–25 calls InnerTube search; SearchViewModel.swift lines 335–369 blocks local results behind primary YouTube result | Local-first database search, independent authorized catalogue results |
| Autocomplete | SearchViewModel.swift calls SearchSuggestions.suggest | Independent suggestions, optionally local suggestion cache |
| Other providers | SearchViewModel.swift lines 373–408 searches Audius, Qobuz, JioSaavn and addons *only after* YouTube resolution | Search those concurrently, not after YouTube |
| Home | HomeViewModel.swift lines 180,205,269,308,339 browses InnerTube | Local recommendations and permitted catalogue feeds |
| Album page | AlbumDetailView.swift lines 17–38 calls InnerTube browse; album save lines 66–69 calls YouTube mutations | Trop release identity and local saves |
| Artist page | ArtistDetailView.swift lines 23–38 calls InnerTube browse; follow lines 1068–1090 mirrors to YouTube | Trop artist ID, local follow records |
| Podcast page | PodcastDetailView.swift lines 42–55 calls InnerTube browse; lines 84–98 subscription operations | RSS/feed-indexed shows and episodes, local subscriptions |
| Podcast alternative | PodcastIndexClient.swift + PodcastMetadataResolver.swift already query Podcast Index or iTunes | Reuse for independent discovery/detail; feed and episode GUID identity |
| Metadata | MetadataResolver.swift tries iTunes, Deezer, then MusicBrainz; not entirely YouTube-dependent | Validate licences and recording/release confidence; PR #56 read-only identities |
| Favorites | LikeStore.swift lines 36–62 mutates YouTube for legacy video IDs | Always local-first, then CloudKit/authorized opt-in sync |
| Library refresh | SyncBridge.swift wires four InnerTube sync/mutation services; LibraryView.swift lines 92–112 can request account info and full YTM sync | Trop-owned GRDB truth, safe import/migration |
| Playlist edits | LibraryView.swift 519–584 and 667–686 supports YT mutations | Own playlist UUID, stable entry IDs and positions |
| History | PlaybackStateService.swift lines 195–249 records locally and also registers YTM playback URL | Local only by default; opt-in scrobble separate |
| Similar autoplay | NowPlaying.swift lines 776–810 references YouTube IDs | Provider-neutral recommendations |
| Account polling | AccountSheetHost.swift lines 40–90 calls InnerTube accountInfo; LibraryView.swift opens it | Remove music-library dependency on YouTube cookies |
| Audio resolution | Separate providers already available through PlaybackManager and SearchViewModel | Retain only authorized transport/source resolver |

## Serious performance finding

SearchViewModel.fetchResults starts an async local GRDB query, but **awaits the YouTube search before it uses local results** (roughly lines 335–363). Its Audius/Qobuz/JioSaavn/addon queries start only afterward. A slow YouTube result therefore delays both local library results and independent catalogues. Local-first rendering and parallel provider search are a **real** possible speed improvement, even without iCloud.

## Serious integrity finding — repeated playlist entries

DatabaseMigrations.swift v1 defines the playlist_song_map UNIQUE constraint on (playlist_id, song_id) around line 86. TropLibraryStore.insertMapsIgnoringConflicts inserts with INSERT OR IGNORE. As a result, the legacy table **cannot preserve repeated occurrences of the same recording in one playlist**. PR #57's new independent playlist membership UUID supports repeats at the model level, but does not yet change GRDB or migrate stored data. Add a new table/dual-read strategy with rollback and preserved positions before claiming lossless migration.

## Serious integrity finding — YT refresh can alter Trop saves

TropLibraryStore.applyArtistSync, applyPlaylistSync and unmarkStaleLikedSongs reconcile saved flags against remote YTM state. A stale/partial refresh must never become a deletion command after Trop owns the library. Protect local favorites, playlist order, artist/podcast follows and cloud tombstones first, then retire the remote sync.

## Privacy and efficiency

Private iPhone logs repeatedly show accountInfo requests even before any selected song, and HTTP 400 INVALID_ARGUMENT from InnerTube while non-YouTube providers play. AccountSheetHost.fetchAccountInfo and LibraryView triggers are real call paths. Avoid logging account names, login token lengths, playback tracking URLs and Last.fm API keys in future diagnostics.

## Safe release plan

1. Preserve old song, album, artist, podcast and playlist IDs as **reversible aliases**, introduce own Trop UUIDs and verify mapping against actual studio recordings. Never delete legacy rows first.
2. Make local songs/playlists visible immediately without waiting for YouTube. Query independent catalogue providers concurrently; show ambiguous or unavailable matches explicitly.
3. Promote independent release/artist and Podcast Index + RSS browsing into UI. Do not choose wrong masters, fan videos or different edits by title alone.
4. GRDB dual-read / transactional migration for saved records and per-occurrence playlist entries. Include likes, episodes, history, rollback, retries, conflicts and offline.
5. Implement CKSyncEngine private-zone sync and durable outbox. Test two devices, account changes, stale/empty cloud, concurrent playlist reorder and sign-out. **No downloaded audio.**
6. Remove YTM account polling, library mutations, full sync, autoplay and playback registration after data equivalence is proved. Keep a separated, authorized source resolver if terms allow it.
7. Verify iOS UI behavior, latency, legal/commercial metadata and artwork rights, source reliability and privacy before merging.

## Current draft PRs

- Trop #56: read-only MusicBrainz identities and test suite, iOS build green, **not enabled in live UI**: https://github.com/Mosas123/Trop/pull/56
- Trop #57: metadata-only iCloud model types, Swift 6 tests, **no CKSyncEngine, entitlements or migration**: https://github.com/Mosas123/Trop/pull/57
- ApoloEngine #27: real AVPlayerItem EOF timeline capture, 122/122 CI, confirmed on iPhone: https://github.com/Mosas123/ApoloEngine/pull/27
- ApoloEngine #28: clock/uptime, rate and access-log diagnosis of repeatable ~21s drift: https://github.com/Mosas123/ApoloEngine/pull/28
- Trop #58: experimental EOF-evidence IPA on iPhone: https://github.com/Mosas123/Trop/pull/58

## Primary technical references

- Apple CKSyncEngine: https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5
- Apple AVPlayerItemAccessLogEvent: https://developer.apple.com/documentation/avfoundation/avplayeritemaccesslogevent
- MusicBrainz API rate limits: https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting
- YouTube API Services Developer Policies: https://developers.google.com/youtube/terms/developer-policies
