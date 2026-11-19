# HLS native timed-metadata — experimental iPhone IPA

**Warning: this IPA deliberately re-enables an AVFoundation path involved in a previous iOS 27.0.1 EXC_BAD_ACCESS. It can crash.** This is for controlled diagnosis only; not a fix or a production upgrade.

## Isolated change
- Branch derives from the working Thrum diagnostic PR #18.
- ApoloEngine Swift package pinned to experimental commit `80c0f71ee8616ded3bbb0f37415ef11519b5c253` (engine PR #12, based on PR #11).
- In the engine, native HLS timed metadata is enabled only for `.m3u8` or explicit HLS MIME and requests **only** ID3/common song title identifiers.
- MP3/AAC native live, FFmpeg/ICY, music, Dolby, MPVKit and app resume logic remain unchanged. The general engine branch still keeps the HLS metadata output disabled.

## Hardware protocol
1. Keep the previous working IPA available for rollback.
2. Install this **experimental** IPA; enable **ApoloEngine Beta (Live Radio)**, independent of music beta.
3. Play a station known to use native HLS with changing title metadata (do not use an MP3/ICY station as sole test).
4. Observe title update and radio playback for 2 minutes, then change HLS stations several times and try background, lock, AirPods and pause/resume.
5. If the app crashes: **stop testing**, save the full iOS Analytics `.ips` crash report for Trop/AVFCore and the timestamp/station name, and reinstall the stable IPA.
6. If no crash, continue longer soak to check memory/metadata updates. No claim of safety from one successful trial.

The engine emits source-free `APOLO_HLS_META attach/titleAccepted/detach` diagnostics to the device console. No raw station token, headers or title values in those messages.

Please avoid releasing or merging this branch. Engine code and standalone radio production stability cannot be certified from CI alone.
