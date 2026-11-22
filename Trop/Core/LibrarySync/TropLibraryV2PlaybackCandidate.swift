import Foundation

/// A playback item is a candidate to save, not the authoritative Trop ID.
/// The user must explicitly choose Save or Add to Playlist.
struct TropLibraryV2PlaybackCandidate: Sendable {
    let title: String
    let artist: String?
    let durationSeconds: Int
    let provider: String
    let externalID: String

    static func sourceReference(for playbackID: String) -> (
        provider: String, externalID: String
    )? {
        if let catalogue = MusicCatalogID(storageKey: playbackID) {
            return (catalogue.source.rawValue, catalogue.rawValue)
        }
        if MusicPlaybackIdentity.isYouTube(playbackID) {
            return ("youtube", playbackID)
        }
        // Live radio, podcast transient IDs, or unsupported providers must
        // not be mistaken for a canonical recording.
        return nil
    }

    @MainActor
    static func current() -> TropLibraryV2PlaybackCandidate? {
        let player = NowPlaying.shared
        guard let playbackID = player.videoId, !playbackID.isEmpty else {
            return nil
        }
        guard let source = sourceReference(for: playbackID) else { return nil }
        let duration = player.duration.isFinite
            ? max(0, Int(min(player.duration, Double(Int.max / 2))))
            : 0
        return TropLibraryV2PlaybackCandidate(
            title: player.displayTitle,
            artist: player.displayArtist,
            durationSeconds: duration,
            provider: source.provider,
            externalID: source.externalID
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
