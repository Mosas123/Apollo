import Foundation

/// YouTube Music distinguishes a label's audio-only art track (ATV) from
/// an official music video (OMV) or user-uploaded video (UGC). A stream URL
/// with audio channels does NOT mean its recording is the album audio.
enum MusicRecordingSelectionPolicy {
    static func isVideoRecording(_ type: String?) -> Bool {
        type == "MUSIC_VIDEO_TYPE_OMV" || type == "MUSIC_VIDEO_TYPE_UGC"
    }

    static func isStudioAudio(_ type: String?) -> Bool {
        type == "MUSIC_VIDEO_TYPE_ATV"
    }

    static func isMusicVideo(isVideo: Bool?, type: String?) -> Bool {
        isVideo == true || isVideoRecording(type)
    }

    /// Only rematch when the request was for a *song* and the resolved source
    /// is positively identified as a video. Unknown types stay untouched.
    static func shouldFindAlbumAudio(
        selectedVideo: Bool,
        rowType: String?,
        sourceType: String?,
        rowIsVideo: Bool = false,
        albumKnown: Bool = false,
        expectedDuration: Int = 0,
        resolvedDuration: Int = 0
    ) -> Bool {
        // A video ID is not an explicit request to hear its soundtrack.
        // Only a user choosing Videos asks for the video recording.
        guard !selectedVideo, !isStudioAudio(sourceType) else { return false }
        if rowIsVideo || isVideoRecording(rowType)
            || isVideoRecording(sourceType) { return true }

        // Old saved library rows and some InnerTube responses omit
        // musicVideoType. With a known album, an untyped source merits a
        // verified ATV lookup, particularly if its timing is inconsistent.
        if albumKnown, sourceType == nil { return true }
        return albumKnown && expectedDuration > 0
            && resolvedDuration > 0
            && abs(expectedDuration - resolvedDuration) > 18
    }

    /// Do not use fuzzy substring title matches for audio substitution.
    /// Exact recording title, real performer credits and close duration or
    /// verified album identity are required. Remixes/live/covers must not
    /// silently become the studio version or vice versa.
    static func verifiedAlbumAudio(
        wantedTitle: String,
        wantedArtist: String,
        wantedAlbum: String?,
        wantedDuration: Int,
        candidateTitle: String,
        candidateArtists: [String],
        candidateAlbum: String?,
        candidateDuration: Int,
        candidateType: String?,
        originalWasVideo: Bool = false
    ) -> Bool {
        guard isStudioAudio(candidateType),
              !wantedArtist.isEmpty,
              candidateArtists.contains(where: {
                  // Cross-catalogue fuzzy artist matching accepts
                  // "Bad Bunny Tribute" as a substring of "Bad Bunny".
                  // Recording substitution requires stricter identity.
                  TextMatch.normalizeArtist($0)
                      == TextMatch.normalizeArtist(wantedArtist)
              }),
              TextMatch.recordingsMatch(wantedTitle, candidateTitle),
              !TextMatch.isSuspiciousVersion(candidateTitle)
        else { return false }

        let targetAlbum = TextMatch.normalizeTitle(wantedAlbum ?? "")
        let sourceAlbum = TextMatch.normalizeTitle(candidateAlbum ?? "")
        if !targetAlbum.isEmpty, !sourceAlbum.isEmpty,
           !TextMatch.albumsMatch(wantedAlbum ?? "", candidateAlbum ?? "") {
            return false
        }

        // An album match can substitute for missing duration. Otherwise
        // demand time alignment; two same-name recordings can be different.
        let sameAlbum = !targetAlbum.isEmpty
            && !sourceAlbum.isEmpty
            && TextMatch.albumsMatch(wantedAlbum ?? "", candidateAlbum ?? "")
        if wantedDuration <= 0 || candidateDuration <= 0 {
            return sameAlbum
        }
        // A music video may include a spoken introduction or outro that
        // is absent from the official studio master. The exact release
        // identity allows a wider range than a title/artist-only match.
        // A confirmed video often has a 30–60 second scene around a
        // 3-minute song. Exact artist/title plus an official ATV identity
        // justify the wider limit even if the old video row has no album.
        let maxDifference = (sameAlbum || originalWasVideo) ? 60 : 20
        return abs(wantedDuration - candidateDuration) <= maxDifference
    }
}
