# iOS 27 recovery diagnostics — iPhone protocol

## Purpose and safety
This branch only instruments the existing audio recovery flow on top of Trop PR #17. It does not change session ownership, pause/resume policy, Apolo rendering, MPVKit fallback, watchdog deadlines, Lossless, Atmos, radio, or AirPods behavior.
The three iOS 27-only session lifecycle notifications are NOT instrumented in this build: the available GitHub Actions Xcode 26.6 uses the iOS 26.5 SDK and cannot compile their declarations. The existing legacy interruption notification and UIKit background/foreground/active callbacks are instrumented without changing playback decisions.

## Reading the log
Filter for AUDIO_RECOVERY and AUDIO_SESSION_ACTIVATION. uptimeMs is monotonic uptime in milliseconds. Trace id and sinceBeginMs / sinceEndMs correlate events after a traditional interruption began. sinceEndMs=-1 means there has been no end notification yet.
UIKit foreground/background events may precede a traditional interruption; compare their uptimeMs values even if no trace id exists.
Events include application background/foreground/active, legacy interruption begin/end/suspension, audio activation success or failure with stage and duration, resume command, Thrum UI playing, Apolo playing, media-clock advance, and MPV fallback.
Important: the AUDIO_SESSION_ACTIVATION measurement covers category and multichannel setup as well as setActive(true), so it is total synchronous assertion duration rather than an isolated setActive call.
The new diagnostic messages avoid printing signed media URLs, music identifiers, headers, credentials, and audio data.

## Reproduction
1. Use the unsigned IPA from this diagnostic PR Nightly Build, signed/sideloaded with the usual test process. Enable ApoloEngine Beta (Music Only).
2. Begin a finite song; wait at least 30 seconds.
3. Open Instagram with audio and then leave Instagram without reopening Thrum. Note the instant of exit and instant sound becomes audible, ideally with an external stopwatch or screen recording.
4. Capture logs from 20 seconds before interruption until 30 seconds after audio comes back. Include the full lines matching the two diagnostic prefixes.
5. Repeat with short and long interruptions, a paused-before-interruption track, AirPods, lock screen, and background/suspension.
6. Confirm a genuinely stalled new load still falls back after the existing continuous 20-second pending window.

## Interpretation
- Legacy interruption began-to-ended duration is notification separation, NOT time spent waiting for Apolo or user time in Instagram.
- The new iOS 27-specific resumption recommendation is not captured by this IPA. If legacy end arrives late, compare the iPhone stopwatch with UIKit and backend events; a future Xcode/iOS SDK upgrade is required for the new OS notifications.
- If activation fails or consumes time, investigate session ownership and repeated metadata-triggered assertions before modifying the decoder.
- If activation succeeds immediately but the Apolo clock does not advance, inspect renderer state and next instrument the actual audio output pipeline.
- A media-clock advance is NOT evidence that PCM was heard by the user. The 300ms monitor interval adds sampling uncertainty.
- UI playing is set before audio is acoustically confirmed; never treat it as first audible sample.

## Acceptance / release gates
CI build and IPA artifact first; then physical iOS 27 testing. Keep this PR draft and do not merge without reviewed log evidence and owner sign-off.
Apple: https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions
Apple: https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification