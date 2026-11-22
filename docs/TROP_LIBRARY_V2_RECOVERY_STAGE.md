# Trop Library V2 recovery — experimental stage (22 Nov 2026)

**PR #80 is DRAFT on PR #79; never merge or promote recovery to final without round-trip QA.**

## What is implemented

- A versioned **V2-only** metadata archive, schema v2, with sorted-key JSON
  and SHA-256 checksum verification (detects accidental corruption only).
- A consistent single GRDB read of six V2 tables: items, source aliases,
  playlist entries, radio favorites, legacy import membership ledger and
  album/episode parent relations.
- A staged atomic **restore into completely empty V2 tables**. It refuses
  to touch a populated V2 library or an ephemeral database, and rejects
  invalid versions, checksums, IDs and referential integrity.
- A read-only **Settings → Experimental library → Experimental V2 Snapshot**
  Files export/verify screen (only visible while V2 preview is enabled).
  There is **no restore button** in the app.
- Lossless preservation of membership UUIDs, order/duplicates and import
  tombstones for already-backed-up records.

## Material safety limitation

Some provider IDs use `addon:` + encoded manifest references. A manifest may
contain an access token or private URL. Export **omits unknown/private aliases**
instead of copying them. The archive reports the number omitted; their song
metadata and playlist placement remain, but playback must be re-linked after
restoration. This is deliberate data minimization, not perfect portability.

The exported JSON file is **NOT ENCRYPTED**. Keep it private. It excludes audio,
local download paths, cookies, cloud tokens and remote playback URLs.
Provider-generated IDs outside the allowlist are also withheld. A checksum
is not proof of origin or cryptographic authenticity.

## Still not safe to uninstall or move phones

This snapshot **does not include the old/legacy library tables**. PR #67 has
a separate legacy metadata-only export, but it neither restores nor covers
pre-existing V2 data and must be reconciled before we advertise a **complete
rescue backup**. Do not infer that having a checksum means we can safely
rebuild someone's entire library.

Before activating V2 restore/import for a user:

1. Integrate a single legacy+V2 archive and **real transactional restore**
   with a clear merge-vs-empty policy; account for private addon identities.
2. Run direct GRDB restore round-trip and malformed-input rollback tests
   (current SQLite fixtures exercise the schema and invariants, not the
   actual Swift GRDB method).
3. Validate user deletions, duplicate entries, overlapping aliases,
   partial/crashed import, app restart and large libraries on fixtures.
4. Verify Files exporter/importer, sandbox permissions, privacy and data
   persistence on an iPhone; no Mac required for the user's QA.
5. Add explicit user confirmation and recovery path, then a single
   integrated IPA. Do not merge to main prematurely.
