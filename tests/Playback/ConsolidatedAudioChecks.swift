import Foundation

@main
struct ConsolidatedAudioChecks {
    private static var passed = 0

    private static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        passed += 1
    }

    static func main() {
        expect(TextMatch.versionsCompatible(
            "Niagara Falls (Foot or 2)",
            "Niagara Falls (Foot or 2)"
        ), "Same vocal recording")
        expect(!TextMatch.versionsCompatible(
            "Niagara Falls (Foot or 2)",
            "Niagara Falls (Foot or 2) (Instrumental)"
        ), "Vocal vs instrumental are distinct recordings")
        expect(!TextMatch.titlesMatch(
            "Niagara Falls (Foot or 2)",
            "Niagara Falls (Foot or 2) [Instrumental]"
        ), "Fuzzy titles must not collapse instrumentals")
        expect(!TextMatch.albumsMatch(
            "HEROES & VILLAINS",
            "HEROES & VILLAINS (Instrumentals)"
        ), "Album edition identity is mandatory")
        expect(TextMatch.albumsMatch(
            "HEROES & VILLAINS",
            "HEROES & VILLAINS"
        ), "Identical original albums match")
        expect(TextMatch.isSuspiciousVersion(
            "Niagara Falls (Instrumental)"
        ), "Suspicious marker must survive title normalization")
        expect(!TextMatch.recordingsMatch(
            "Niagara Falls (Foot or 2)",
            "Niagara Falls (Foot or 2) (Instrumental)"
        ), "Studio verification must reject instrumental variants")
        expect(!TextMatch.titlesMatch(
            "Moscow Mule", "Moscow Mule (Live)"
        ), "Live recording differs from studio")
        expect(!TextMatch.titlesMatch(
            "Moscow Mule", "Moscow Mule (Remix)"
        ), "Remix recording differs from original")
        expect(!TextMatch.albumsMatch(
            "Album", "Album (Karaoke)"
        ), "Karaoke album differs from original")
        expect(TextMatch.titlesMatch(
            "Moscow Mule", "Moscow Mule (Official Audio)"
        ), "Official audio promo suffix is safe")
        expect(TextMatch.recordingsMatch(
            "Moscow Mule (Official Audio)", "Moscow Mule"
        ), "Recording comparer still strips promotional labels")
        expect(TextMatch.normalize(
            "HEROES & VILLAINS"
        ) != TextMatch.normalize(
            "HEROES & VILLAINS (Instrumentals)"
        ), "Full edition identity can partition addon caches")
        let niagaraVocal = MusicRecordingSelectionPolicy.WantedRecording(
            title: "Niagara Falls (Foot or 2)",
            artist: "Metro Boomin",
            album: "HEROES & VILLAINS",
            duration: 208,
            originalWasVideo: false
        )
        expect(!MusicRecordingSelectionPolicy.verifiedAlbumAudio(
            wanted: niagaraVocal,
            candidate: .init(
                title: "Niagara Falls (Foot or 2)",
                artists: ["Metro Boomin"],
                album: "HEROES & VILLAINS (Instrumentals)",
                duration: 208,
                type: "MUSIC_VIDEO_TYPE_ATV"
            )
        ), "ATV type alone cannot override a wrong album edition")
        expect(!MusicRecordingSelectionPolicy.verifiedAlbumAudio(
            wanted: niagaraVocal,
            candidate: .init(
                title: "Niagara Falls (Foot or 2) (Instrumental)",
                artists: ["Metro Boomin"],
                album: "HEROES & VILLAINS",
                duration: 208,
                type: "MUSIC_VIDEO_TYPE_ATV"
            )
        ), "ATV title qualifier cannot override vocal song")
        expect(OfflineAudioFormatPolicy.isVerifiedFLAC(
            qualityTier: "Lossless", mimeType: "audio/flac",
            pathExtension: "flac"
        ), "Actual FLAC is downloadable")
        expect(OfflineAudioFormatPolicy.isVerifiedFLAC(
            qualityTier: "Lossless", mimeType: "audio/x-flac",
            pathExtension: ""
        ), "FLAC may have an opaque signed URL")
        expect(!OfflineAudioFormatPolicy.isVerifiedFLAC(
            qualityTier: "Atmos", mimeType: "audio/eac3",
            pathExtension: "flac"
        ), "E-AC3 Atmos must NEVER enter FLAC branch")
        expect(!OfflineAudioFormatPolicy.isVerifiedFLAC(
            qualityTier: "Lossless", mimeType: "audio/eac3",
            pathExtension: "flac"
        ), "Contradictory MIME cannot be mislabeled FLAC")
        expect(!OfflineAudioFormatPolicy.isVerifiedFLAC(
            qualityTier: "Lossless", mimeType: "audio/mp4; codecs=ec-3",
            pathExtension: "flac"
        ), "Dolby EC-3 in MP4 cannot be remuxed as FLAC")
        expect(!OfflineAudioFormatPolicy.isVerifiedFLAC(
            qualityTier: "High", mimeType: "audio/flac",
            pathExtension: "flac"
        ), "Lossless tier must be verified")
        expect(!OfflineAudioFormatPolicy.isVerifiedFLAC(
            qualityTier: "Lossless", mimeType: "audio/aac",
            pathExtension: "flac"
        ), "AAC stream cannot masquerade as FLAC")
        expect(!OfflineAudioFormatPolicy.isVerifiedFLAC(
            qualityTier: "Lossless", mimeType: "application/octet-stream",
            pathExtension: "flac"
        ), "Unknown media MIME is insufficient proof of lossless FLAC")
        print("PASS: \(passed) recording-edition and offline-codec checks")
    }
}
