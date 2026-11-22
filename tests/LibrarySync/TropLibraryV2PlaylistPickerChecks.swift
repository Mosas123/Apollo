import Foundation

// Minimal app-type stubs allow the real identity/candidate code to compile
// in strict Swift 6 without importing a UIKit player or an iOS database.
struct SongItem: Sendable {
    let videoId: String
    let title: String
    let artistNamesDisplay: String
    let duration: Int
}

@MainActor
final class NowPlaying {
    static let shared = NowPlaying()
    var videoId: String?
    var duration: Double = 0
    var displayTitle = ""
    var displayArtist = ""
}

enum TropLibraryV2Store {
    static func savePlaybackRecording(
        title: String, artist: String?, durationSeconds: Int,
        provider: String, externalID: String, liked: Bool
    ) async throws -> String { "test-recording" }
}

@main
@MainActor
struct TropLibraryV2PlaylistPickerChecks {
    static func main() {
        let opaqueID = "eyJrIjoiZXhhbXBsZSJ9" // harmless fixture, no real install URL
        let addonID = "addon:" + opaqueID
        let addon = SongItem(
            videoId: addonID, title: "A track", artistNamesDisplay: "An artist",
            duration: 187
        )
        guard let candidate = TropLibraryV2PlaybackCandidate.fromSong(addon) else {
            fatalError("An add-on song must be eligible for a local V2 playlist")
        }
        precondition(candidate.provider == "addon")
        precondition(candidate.externalID == opaqueID)
        precondition(candidate.title == "A track")
        precondition(candidate.artist == "An artist")
        precondition(candidate.durationSeconds == 187)

        let youtube = TropLibraryV2PlaybackCandidate.fromSong(SongItem(
            videoId: "localvideo01", title: "YouTube", artistNamesDisplay: "Singer",
            duration: 202
        ))
        precondition(youtube?.provider == "youtube")
        precondition(youtube?.externalID == "localvideo01")

        let nullbeat = TropLibraryV2PlaybackCandidate.fromSong(SongItem(
            videoId: "addon:abc", title: "NullBeat", artistNamesDisplay: "Singer",
            duration: -1
        ))
        precondition(nullbeat?.provider == "addon")
        precondition(nullbeat?.externalID == "abc")
        precondition(nullbeat?.durationSeconds == 0)

        let unsupported = TropLibraryV2PlaybackCandidate.fromSong(SongItem(
            videoId: "radio:live", title: "Live", artistNamesDisplay: "DJ",
            duration: 0
        ))
        precondition(unsupported == nil)
        let current = NowPlaying.shared
        current.videoId = addonID
        current.displayTitle = "Live metadata"
        current.displayArtist = "An artist"
        current.duration = 187
        precondition(TropLibraryV2PlaybackCandidate.current()?.provider == "addon")
        print("Trop V2 picker identity checks passed")
    }
}
