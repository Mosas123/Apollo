import Foundation

@main
enum TropLibraryV2IdentityChecks {
    static func main() throws {
        let playlist = TropLibraryV2IdentityPolicy.newID()
        let recording = TropLibraryV2IdentityPolicy.newID()
        assert(playlist != recording)
        assert(TropLibraryV2IdentityPolicy.isCanonicalID(playlist))
        assert(TropLibraryV2IdentityPolicy.checkedID(recording) == recording)
        assert(!TropLibraryV2IdentityPolicy.isCanonicalID("youtube-video-id"))

        let name = try TropLibraryV2IdentityPolicy.checkedTitle("  My playlist  ")
        assert(name == "My playlist")
        assert(try TropLibraryV2IdentityPolicy.checkedOptionalText("  Artist ") == "Artist")
        assert(try TropLibraryV2IdentityPolicy.checkedOptionalText(" ") == nil)

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

        assert(Set(TropLibraryV2Kind.allCases.map(\.rawValue)).count == 6)
        print("Trop Library V2 identity checks passed")
    }
}
