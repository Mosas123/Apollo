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
        sourceType: String?
    ) -> Bool {
        !selectedVideo
            && (isVideoRecording(rowType) || isVideoRecording(sourceType))
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
        candidateType: String?
    ) -> Bool {
        guard isStudioAudio(candidateType),
              !wantedArtist.isEmpty,
              candidateArtists.contains(where: {
                  TextMatch.artistsMatch($0, wantedArtist)
              }),
              TextMatch.recordingsMatch(wantedTitle, candidateTitle),
              !TextMatch.isSuspiciousVersion(candidateTitle)
        else { return false }

        let targetAlbum = TextMatch.normalizeTitle(wantedAlbum ?? "")
        let sourceAlbum = TextMatch.normalizeTitle(candidateAlbum ?? "")
        if !targetAlbum.isEmpty, !sourceAlbum.isEmpty,
           !TextMatch.albumsMatch(targetAlbum, sourceAlbum) {
            return false
        }

        // An album match can substitute for missing duration. Otherwise
        // demand time alignment; two same-name recordings can be different.
        let sameAlbum = !targetAlbum.isEmpty
            && !sourceAlbum.isEmpty
            && TextMatch.albumsMatch(targetAlbum, sourceAlbum)
        if wantedDuration <= 0 || candidateDuration <= 0 {
            return sameAlbum
        }
        return abs(wantedDuration - candidateDuration) <= 8
    }
}
