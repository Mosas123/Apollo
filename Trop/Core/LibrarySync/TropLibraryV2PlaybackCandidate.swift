import Foundation

/// A playback item is a candidate to save, not the authoritative Trop ID.
/// The user must explicitly choose Save or Add to Playlist.
struct TropLibraryV2PlaybackCandidate: Sendable {
    let title: String
    let artist: String?
    let durationSeconds: Int
    let provider: String
    let externalID: String

    @MainActor
    static func current() -> TropLibraryV2PlaybackCandidate? {
        let player = NowPlaying.shared
        guard let playbackID = player.videoId, !playbackID.isEmpty else {
            return nil
        }
        let provider: String
        let externalID: String
        if let catalogue = MusicCatalogID(storageKey: playbackID) {
            provider = catalogue.source.rawValue
            externalID = catalogue.rawValue
        } else if MusicPlaybackIdentity.isYouTube(playbackID) {
            provider = "youtube"
            externalID = playbackID
        } else {
            // A live radio station or a transient identifier is not proof of
            // a stable recording identity; reject it instead of guessing.
            return nil
        }
        let duration = player.duration.isFinite
            ? max(0, Int(min(player.duration, Double(Int.max / 2))))
            : 0
        return TropLibraryV2PlaybackCandidate(
            title: player.displayTitle,
            artist: player.displayArtist,
            durationSeconds: duration,
            provider: provider,
            externalID: externalID
        )
    }

    @discardableResult
    func save(liked: Bool = false) async throws -> String {
        try await TropLibraryV2Store.savePlaybackRecording(
            title: title, artist: artist, durationSeconds: durationSeconds,
            provider: provider, externalID: externalID, liked: liked
        )
    }
}
