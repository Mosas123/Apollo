# Protect user-owned library from partial YouTube refreshes

This is a non-destructive migration safety guard, not complete account retirement.

Legacy TropLibraryStore applies InnerTube/YTM results to local GRDB rows.
Previously an incomplete / stale remote list could unbookmark:
- locally saved artists (non-returned IDs)
- saved albums
- followed podcasts
- older liked songs
- entire auto-sync YouTube-linked playlists and their membership

This is incompatible with the future Trop-owned library / private CloudKit
model: an empty, stale or partial provider response must never become an
unlike/unsubscribe/delete on local saved state.

## This draft

- Preserve remote additions and metadata hydration while removing
  remote-inferred deletions from the store reconciliation methods.
- Preserve existing local liked, album/artist/podcast bookmarked states,
  linked playlists and membership when YouTube returns a partial list.
- Retain explicit user-initiated removal methods intact.
- Retain the existing account session and legacy import paths while our
  reversible ID aliases, backup/import preview and cloud outbox are built.
- No CloudKit live writes, no changes to recorded file paths/downloads, no
  alterations to ApoloEngine or FFmpeg.

## Caveats

- Provider results can still add YouTube favorites and metadata to the
  local store; the app is not fully independent yet.
- A removal done on YouTube outside Trop no longer automatically removes
  that row from the local library. That's deliberate: the local library will
  eventually be authoritative and remote activity won't be destructive.
- We cannot yet distinguish all prior remote-origin favorites from user-owned
  actions; future explicitly consented one-time import must record origin.
- LikeStore.toggle() currently may also mirror the user's likes to YouTube
  when logged in. That separate mutation path will be disabled after the
  new local-only CRUD is tested.

## Acceptance

- CI check confirms no SQL remote-absence deletion or unmark path.
- Existing saved albums/artists/podcasts and both local/YouTube-linked
  playlists persist after library refresh.
- Explicit local unlikes/deletes still work.
- One combined iPhone QA IPA via integration PR #64:
  https://github.com/Mosas123/Trop/pull/64
