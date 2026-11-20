import Foundation

@main
struct StudioAudioMatchChecks {
    private static func verified(
        title: String = "Moscow Mule",
        artist: String = "Bad Bunny",
        album: String? = "Un Verano Sin Ti",
        duration: Int = 245,
        candidateTitle: String = "Moscow Mule",
        candidateArtist: [String] = ["Bad Bunny"],
        candidateAlbum: String? = "Un Verano Sin Ti",
        candidateDuration: Int = 245,
        candidateType: String? = "MUSIC_VIDEO_TYPE_ATV",
        originalWasVideo: Bool = false
    ) -> Bool {
        MusicRecordingSelectionPolicy.verifiedAlbumAudio(
            wanted: .init(
                title: title, artist: artist, album: album, duration: duration,
                originalWasVideo: originalWasVideo
            ),
            candidate: .init(
                title: candidateTitle, artists: candidateArtist,
                album: candidateAlbum, duration: candidateDuration, type: candidateType
            )
        )
    }

    static func main() {
        precondition(MusicRecordingSelectionPolicy.isMusicVideo(
            isVideo: nil, type: "MUSIC_VIDEO_TYPE_OMV"
        ), "Official videos must not be mislabeled Songs")
        precondition(MusicRecordingSelectionPolicy.isMusicVideo(
            isVideo: nil, type: "MUSIC_VIDEO_TYPE_UGC"
        ), "UGC videos must not be mislabeled Songs")
        precondition(!MusicRecordingSelectionPolicy.isMusicVideo(
            isVideo: nil, type: "MUSIC_VIDEO_TYPE_ATV"
        ), "Official album art tracks are Songs")
        precondition(MusicRecordingSelectionPolicy.shouldFindAlbumAudio(
            selectedVideo: false,
            rowType: nil, sourceType: "MUSIC_VIDEO_TYPE_OMV"
        ), "A legacy song entry can rematch an OMV stream")
        precondition(!MusicRecordingSelectionPolicy.shouldFindAlbumAudio(
            selectedVideo: true,
            rowType: "MUSIC_VIDEO_TYPE_OMV",
            sourceType: "MUSIC_VIDEO_TYPE_OMV"
        ), "Explicit video playback must never rematch")
        precondition(!MusicRecordingSelectionPolicy.shouldFindAlbumAudio(
            selectedVideo: false, rowType: nil, sourceType: nil
        ), "Unknown type must not trigger unsafe rematching")
        precondition(verified(), "Same artist, album and title ATV accepted")
        precondition(verified(candidateTitle: "Moscow Mule (Official Audio)"),
            "Official-audio suffix does not change the recording")
        precondition(!verified(candidateType: "MUSIC_VIDEO_TYPE_OMV"),
            "A music video is not a verified album master")
        precondition(!verified(candidateArtist: ["Bad Bunny Tribute"]),
            "Artist mismatch should reject cover")
        precondition(!verified(candidateTitle: "Moscow Mule (Live)"),
            "Do not turn a live version into studio audio")
        precondition(!verified(candidateTitle: "Moscow Mule (Remix)"),
            "Do not turn a remix into original audio")
        precondition(!verified(candidateTitle: "Other Song"),
            "Exact recording title is mandatory")
        precondition(!verified(candidateAlbum: "Different Album"),
            "Different release should not match")
        precondition(verified(candidateDuration: 260),
            "An album-verified studio recording can omit video-only intro")
        precondition(!verified(candidateDuration: 330),
            "Excessive duration mismatch must still be rejected")
        precondition(!verified(album: nil, candidateAlbum: nil,
                               candidateDuration: 270),
            "Without release proof, large duration mismatches are rejected")
        precondition(verified(candidateDuration: 252),
            "A small duration difference is acceptable")
        precondition(!verified(album: nil, duration: 0),
            "No duration/album cannot verify identity")
        precondition(verified(duration: 0),
            "Exact album match substitutes for unknown duration")
        precondition(!verified(candidateArtist: []),
            "Do not trust candidates with missing performer credits")
        precondition(!verified(artist: ""),
            "Do not rematch when source artist is unknown")
        // Repro: NUEVAYoL was presented as a 3:42 video soundtrack,
        // while the original album recording is ~3:03 (39s shorter).
        precondition(verified(
            title: "NUEVAYoL", album: "DeBÍ TiRAR MáS FOToS",
            duration: 222, candidateTitle: "NUEVAYoL",
            candidateAlbum: "DeBÍ TiRAR MáS FOToS",
            candidateDuration: 183
        ), "NUEVAYoL album recording must survive the video intro offset")
        precondition(verified(
            title: "NUEVAYoL", album: nil, duration: 222,
            candidateTitle: "NUEVAYoL", candidateAlbum: "DeBÍ TiRAR MáS FOToS",
            candidateDuration: 183, originalWasVideo: true
        ), "Known video intro can differ 39s even if old row lacks album")
        precondition(!verified(
            title: "NUEVAYoL", album: nil, duration: 222,
            candidateTitle: "NUEVAYoL", candidateAlbum: "DeBÍ TiRAR MáS FOToS",
            candidateDuration: 183, originalWasVideo: false
        ), "An unknown source cannot permit a 39s duration mismatch")
        precondition(MusicRecordingSelectionPolicy.shouldFindAlbumAudio(
            selectedVideo: false,
            rowType: "MUSIC_VIDEO_TYPE_OMV",
            sourceType: "MUSIC_VIDEO_TYPE_OMV",
            rowIsVideo: true
        ), "Songs tap must seek album audio even for an OMV-classified row")
        precondition(!MusicRecordingSelectionPolicy.shouldFindAlbumAudio(
            selectedVideo: true,
            rowType: "MUSIC_VIDEO_TYPE_OMV",
            sourceType: "MUSIC_VIDEO_TYPE_OMV",
            rowIsVideo: true
        ), "Videos tap must keep the intentionally selected video audio")
        precondition(MusicRecordingSelectionPolicy.shouldFindAlbumAudio(
            selectedVideo: false, rowType: nil, sourceType: nil,
            albumKnown: true, expectedDuration: 222, resolvedDuration: 222
        ), "Untyped album rows must seek a verified ATV when possible")
        precondition(!MusicRecordingSelectionPolicy.shouldFindAlbumAudio(
            selectedVideo: false, rowType: nil,
            sourceType: "MUSIC_VIDEO_TYPE_ATV",
            albumKnown: true
        ), "A verified album track must not be searched again")
        precondition(!MusicRecordingSelectionPolicy.shouldFindAlbumAudio(
            selectedVideo: false, rowType: nil, sourceType: nil,
            albumKnown: false, expectedDuration: 222, resolvedDuration: 222
        ), "Untyped no-album entries should not cause extra searches")
        precondition(!verified(
            title: "NUEVAYoL", album: "DeBÍ TiRAR MáS FOToS",
            duration: 222, candidateTitle: "NUEVAYoL",
            candidateAlbum: "Different Album", candidateDuration: 183,
            originalWasVideo: true
        ), "Even video intro allowance must reject a different album")
        print("PASS: 31 studio album-audio vs music-video matching assertions")
    }
}
