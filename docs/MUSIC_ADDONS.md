# Trop Music Addons — Foundation v1 (Draft)

The goal is a **music-only** addon ecosystem inspired by the flexibility of
Nuvio's addons, with a deliberately small, verifiable, declarative protocol.
This PR is **foundation only**: it does not fetch or install remote manifests
from the UI, store installations on disk, call provider APIs, play remote
streams, or execute arbitrary JavaScript. No source has been activated.

## Manifest shape

Example: docs/examples/music-addon-manifest.json

{
  "schemaVersion": 1,
  "id": "demo.music",
  "name": "Example Music Provider",
  "version": "1.0.0",
  "description": "Documentation-only example. Not a live audio service.",
  "capabilities": ["search", "lyrics"],
  "endpoints": {
    "search": "/v1/search",
    "lyrics": "/v1/lyrics"
  }
}

A user-supplied URL would point to
https://addons.example.org/music/manifest.json (illustrative only). The
manifest declares the provider's capabilities; it does **not** grant
permission to make network requests or run scripts. Only a separately
authorized action may invoke an endpoint in a future PR.

Capabilities reserved in v1: search, catalog, stream, lyrics, metadata,
history. A manifest must declare at least one capability, without
duplicates. The endpoints dictionary must exactly match the capabilities.

Every endpoint is a root-relative **same-origin path**, not a URL.
Valid: /v1/search. Invalid: http://host/search, //host/search, /a/../b,
percent-escaped routes, query strings and fragments.

## Security invariants in this PR

- Only HTTPS manifest URLs with a full public-looking domain and a final
  /manifest.json path are accepted (no credentials or query parameters).
  Loopback/IP literals, .local, .internal and suspicious path encodings
  are rejected.
- The JSON payload is limited to 64 KiB. Schema version, IDs, semver and
  capabilities are validated before the registry accepts an installation.
- An addon installation is **disabled by default**. Users must explicitly
  enable it. A manifest update that adds a capability fails until additional
  permission is requested and accepted in a later UI flow.
- Installation identity uses the canonical manifest URL + provider ID, not
  the provider's ID alone, so independent community sources do not collide.
- The registry has a hard ceiling of 30 installations; duplicate installs
  are rejected; updates and removal only operate on known installations.
- This PR does not execute downloaded code, evaluate JSON expressions,
  issue arbitrary HTTP requests, read private files, or ask for tokens.

**Important:** URL validation in the parser is *not* enough to protect
against DNS rebinding, CNAMEs resolving to private addresses or redirects.
Before a future PR performs any user-configured network fetch, the fetcher
must separately implement DNS/IP checks, redirect validation, limits on
responses and requests, request timeouts, and safe URL handling. No
remote-network feature should ship until those guards are tested.

## Roadmap — separate, reviewable PRs

1. **PR #5 (this PR):** data contracts, validation, consent-first registry,
   standalone Swift 6 tests.
2. **Next PR:** opt-in installation UI, secure persistence, policy-enforcing
   network fetcher, per-provider enable/disable/remove/test.
3. **After that:** capability-specific HTTP adapters for catalog/search,
   then other features. Provider endpoints must have a documented JSON
   response schema, scoped identifiers, and honest rights/DRM handling.
4. **Later:** history imports (with per-source provenance and deduplication),
   consented credentials stored in Keychain, and developer documentation
   once the protocol is stable and tested.

An addon must have permission to distribute the content it exposes. This
system must not be used to bypass paywalls, DRM, account restrictions, or
obtain protected tokens from other apps.

## Test

Run: bash scripts/test-music-addons.sh

Uses Swift 6 with only Foundation, no network, private accounts or third
party credentials. The test suite covers invalid manifest URLs, schema
versioning, unsafe paths, missing/duplicate capabilities, duplicate
installation, disabled-by-default behavior, enable/disable and update
permission escalation.

**No PR in this stack should be merged before the owner tests and approves
it.** The test suite is not a substitute for future on-device checks.
