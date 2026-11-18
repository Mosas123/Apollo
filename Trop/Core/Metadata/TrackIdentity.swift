import Foundation

/// Canonical identity for a track. One resolved object feeds artwork, lyrics
/// and metadata so every surface agrees (see matching law in project memory).
struct TrackIdentity: Sendable, Equatable {
    let videoId: String?
    let title: String
    let artist: String
    let album: String?
    let durationSeconds: Int?

    var cacheKey: String {
        "\(TextMatch.normalize(TextMatch.recordingTitle(title)))|\(TextMatch.normalize(TextMatch.queryArtist(artist)))|\(album ?? "")|\(durationSeconds ?? 0)"
    }

    static func make(from song: SongItem) -> TrackIdentity {
        let query = TextMatch.recordingQuery(
            title: song.title,
            artist: song.artists.map(\.name).joined(separator: ", ")
        )
        return TrackIdentity(
            videoId: song.videoId,
            title: query.title,
            artist: query.artist,
            album: song.album,
            durationSeconds: song.duration > 0 ? song.duration : nil
        )
    }
}
