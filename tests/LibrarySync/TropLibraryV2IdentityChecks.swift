import Foundation

@main
enum TropLibraryV2IdentityChecks {
    static func main() throws {
        let playlist = TropLibraryV2IdentityPolicy.newID()
        let recording = TropLibraryV2IdentityPolicy.newID()
        assert(playlist != recording)
        assert(TropLibraryV2IdentityPolicy.isCanonicalID(playlist))
        let checkedRecording = try TropLibraryV2IdentityPolicy.checkedID(recording)
        assert(checkedRecording == recording)
        assert(!TropLibraryV2IdentityPolicy.isCanonicalID("youtube-video-id"))

        let name = try TropLibraryV2IdentityPolicy.checkedTitle("  My playlist  ")
        assert(name == "My playlist")
        let artist = try TropLibraryV2IdentityPolicy.checkedOptionalText("  Artist ")
        let emptyArtist = try TropLibraryV2IdentityPolicy.checkedOptionalText(" ")
        assert(artist == "Artist")
        assert(emptyArtist == nil)

        do {
            _ = try TropLibraryV2IdentityPolicy.checkedTitle("   ")
            fatalError("Blank playlist names must be rejected")
        } catch TropLibraryV2ValidationError.invalidTitle {}

        let alias = try TropLibraryV2SourceAlias(
            provider: "spotify", scope: "account_1", externalID: "track:abc123"
        )
        assert(alias.provider == "spotify")
        assert(alias.scope == "account_1")
        assert(alias.externalID == "track:abc123")

        for dangerous in [
            "https://example.com/audio?token=123",
            "signed?key=value",
            "/private/var/app/audio.flac",
            "abc#secret",
            "line\nbreak"
        ] {
            do {
                _ = try TropLibraryV2SourceAlias(
                    provider: "youtube", externalID: dangerous
                )
                fatalError("Unsafe alias accepted")
            } catch TropLibraryV2ValidationError.invalidAlias {}
        }

        do {
            _ = try TropLibraryV2SourceAlias(
                provider: "YouTube Music", externalID: "id"
            )
            fatalError("Provider key must be a normalized token")
        } catch TropLibraryV2ValidationError.invalidProvider {}

        do {
            _ = try TropLibraryV2SourceAlias(
                provider: "youtube", scope: "https://secret", externalID: "id"
            )
            fatalError("Scope must not be a URL")
        } catch TropLibraryV2ValidationError.invalidSourceScope {}

        // Saving a V2 recording never implies that an arbitrary metadata
        // alias is playable or that YouTube can be a hidden fallback.
        let audius = try TropLibraryV2SourceAlias(
            provider: "audius", externalID: "D7KyD"
        )
        let qobuz = try TropLibraryV2SourceAlias(
            provider: "qobuz", externalID: "123"
        )
        let addon = try TropLibraryV2SourceAlias(
            provider: "addon", externalID: "install:movie:id"
        )
        let youtube = try TropLibraryV2SourceAlias(
            provider: "youtube", externalID: "DCEVC_sr5Go"
        )
        let mb = try TropLibraryV2SourceAlias(
            provider: "musicbrainz", externalID: "metadata-only"
        )
        let accountScoped = try TropLibraryV2SourceAlias(
            provider: "qobuz", scope: "account_1", externalID: "123"
        )
        let resolvedSource0 = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
            for: [youtube, mb, audius]
        )
        assert(resolvedSource0 == "audius:D7KyD")
        let resolvedSource1 = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
            for: [audius, audius]
        )
        assert(resolvedSource1 == "audius:D7KyD")
        let resolvedSource2 = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
            for: [addon]
        )
        assert(resolvedSource2 == "addon:install:movie:id")

        let resolvedSource3 = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
            for: [qobuz], requiresLossless: true
        )
        assert(resolvedSource3 == "qobuz:123")
        do {
            _ = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
                for: [audius], requiresLossless: true
            )
            fatalError("Lossy playback accepted in lossless mode")
        } catch TropLibraryV2PlaybackSourceError.incompatibleQuality {}

        for unavailable in [
            [TropLibraryV2SourceAlias](), [youtube], [mb],
            [accountScoped], [youtube, mb]
        ] {
            do {
                _ = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
                    for: unavailable
                )
                fatalError("Unverified source accepted")
            } catch TropLibraryV2PlaybackSourceError.unavailable {}
        }
        // Several verified audio links do NOT create extra library songs.
        // Resolve deterministically, with exact recordings ahead of alternates.
        assert(try TropLibraryV2PlaybackSourcePolicy.playbackKey(
            for: [audius, qobuz]
        ) == "qobuz:123")
        assert(try TropLibraryV2PlaybackSourcePolicy.playbackKey(
            for: [audius, qobuz], requiresLossless: true
        ) == "qobuz:123")
        let approvedLive = try TropLibraryV2SourceAlias(
            provider: "addon", scope: "user-approved-alt",
            externalID: "approved-live"
        )
        assert(try TropLibraryV2PlaybackSourcePolicy.playbackKey(
            for: [approvedLive]
        ) == "addon:approved-live")
        assert(try TropLibraryV2PlaybackSourcePolicy.playbackKey(
            for: [approvedLive, qobuz]
        ) == "qobuz:123")

        // YouTube is not a hidden fallback, but saved IDs can play when the
        // user explicitly enables the audio-only provider.
        assert(try TropLibraryV2PlaybackSourcePolicy.playbackKey(
            for: [youtube], allowYouTubeAudio: true
        ) == "DCEVC_sr5Go")
        do {
            _ = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
                for: [youtube], requiresLossless: true,
                allowYouTubeAudio: true
            )
            fatalError("YouTube must not pretend to supply lossless")
        } catch TropLibraryV2PlaybackSourceError.incompatibleQuality {}

        assert(Set(TropLibraryV2Kind.allCases.map(\.rawValue)).count == 6)
        print("Trop Library V2 identity checks passed")
    }
}
