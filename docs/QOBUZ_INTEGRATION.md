# Qobuz (opt-in, account-scoped source)

This is a stacked draft after Audius PRs #1 → #2 → #3. The implementation
is new Swift code: it does not copy GPL-licensed YumaPlayer source or any
third-party, community-shared, bundled, expired or leaked credentials.

## Setup

1. Obtain Qobuz application credentials and an account token that you are
   authorized to use, under Qobuz's API and account conditions.
2. Open Apollo → Settings → Integrations → Qobuz.
3. Enter Application ID, Application secret and user authentication token.
4. Save credentials securely in iOS Keychain (never UserDefaults).
5. Search again. When authenticated and streamable, tracks appear in the
   Qobuz section alongside existing YouTube Music and Audius.
6. Play a track to obtain a fresh full-length CD-quality FLAC URL.

When the account is not configured the Qobuz API is never contacted.
Neither signing secrets nor session tokens are logged.

## Restrictions

- Access to the project source does not grant rights to Qobuz's catalogue.
  The integration requires account/API authorization.
- No embedded community pool, token rotation, proxy fallback, password
  scraping or bypass of previews/subscriptions is included.
- HTTP 401/403/429, regional restrictions, preview/sample content and
  unexpected format IDs are errors, never presented as successful playback.
- Provider-scoped IDs use qobuz:<trackID>; the YouTube resolver is not
  used for Qobuz. SponsorBlock, YouTube auto-radio, duration lookups and
  YouTube-only like calls are avoided on the Qobuz route.
- Requests resolve a fresh signed URL per start. No permanent FLAC URLs
  are stored, and offline Qobuz downloads are deliberately unsupported.
- The current implementation accepts direct HTTPS FLAC URLs, not segmented
  or DRM-protected streaming variants. No workarounds are attempted.
- Verify licensing/partner approval before publishing or distributing.

## Validation and QA

Run: bash scripts/test-qobuz-client.sh (Swift 6 + CryptoKit on macOS).

All unit-test tokens and URLs are fictional. Mocked checks cover parsing,
query encoding, source-scoped identity, authentication headers, request
signing, preview rejection and invalid IDs. Tests do not verify real
Qobuz account access or sound output.

Before merging, test on an authorized Qobuz account with full-track FLAC:
search, playback, end-of-track detection, seeking, background controls,
queue next/previous, track changes, expired URLs, unavailable tracks,
401/403/429 responses, and regression of Audius and YouTube Music.

Docs:
- https://static.qobuz.com/apps/api/QobuzAPI-TermsofUse.pdf
- https://www.qobuz.com/us-en/legal/terms
- https://github.com/MuwMx/YumaPlayer (architectural inspiration only)
