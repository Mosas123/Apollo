# YouTube independence migration — Stage 1: local-first search

**DRAFT / test only.** This stage intentionally starts from Trop/main
and does not depend on the unfinished music catalogue or CloudKit branches.

## Problem in Trop/main

`SearchViewModel.fetchResults` started a GRDB local query concurrently but
waited for the primary InnerTube result before publishing local songs, albums,
artists and playlists. Network failures or slow YouTube requests therefore
made existing offline library entries unnecessarily late to appear.

## Stage 1 change

- Run the GRDB local search as a separate, cancellable task.
- Display local library sections in the existing All Results area **while
  the YouTube sections are not ready**; the Library filter still works.
- Show the normal existing remote sections after they arrive.
- A query that fails on YouTube still shows saved local hits.
- Keep the spinner/loading state while any primary search is in flight;
  do not declare 'no results' because a fast SQLite lookup returned empty.
- Cancel the independent local fetch on query change or search exit, and
  generation-check both responses so an older query cannot replace a new one.
- Add an isolated pure presentation policy and deterministic Swift 6 tests.

## Deliberately not changed

- No changes to `SongEntity` or `videoId`, playlist mapping, likes,
  history, downloads, ApoloEngine, FFmpeg, podcasts or radio.
- No CloudKit iCloud entitlement, live sync, migrations or uploaded audio.
- YouTube is **still** the primary remote search and suggestions source;
  this stage does **not** remove YouTube requests or solve video/studio
  matching yet.
- Audius, Qobuz, JioSaavn and addon searches currently start *after*
  the primary YouTube request; parallel provider discovery is Stage 2.
- Existing remote results can replace the temporary local fallback in
  All Results; the Library filter remains the stable route to saved items.
- Do not merge until CI + mobile QA pass.

## Mobile smoke test checklist

1. Search for a song or artist already saved in Trop; verify it appears
   immediately under the local fallback, even on a poor connection.
2. Switch to the **Library** filter, verify saved songs, playlists, artists
   and albums remain selectable.
3. Search a new term with no saved results; while internet lookup runs,
   show loading rather than instantly showing 'No Results'.
4. Quickly replace query A with query B; an old local or network result
   must never overwrite B.
5. Temporarily test with YouTube unreachable (not airplane mode when the
   source provider needs network); local matches should stay visible.
6. Return to normal connectivity; check existing provider sections and
   regular playback behave as before.

## Acceptance and next steps

CI: `bash scripts/test-local-first-search.sh` + whole-app iOS build.
Test on iPhone; capture sanitized UI behavior with no account credentials.

Next migrations:
- Stage 2: federated catalogue searches concurrently, not waiting for
  YouTube (track provider policy/legal review required).
- Stage 3: stable Trop recording/release/artist/podcast IDs + reversible
  legacy ID alias table.
- Stage 4: transactionally migrate likes, album saves, playlists (including
  duplicate track occurrences), podcasts and episode progress; no deletes.
- Stage 5: CKSyncEngine private iCloud sync of **metadata only**, with
  offline/rollback/tombstone QA and two-device verification.
- Stage 6: remove YouTube library writes, account polling, listening
  tracking, catalogue pages and YTM social sync only after above passes.
