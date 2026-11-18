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
        "\(TextMatch.normalizeTitle(title))|\(TextMatch.normalizeArtist(artist))"
    }

    static func make(from song: SongItem) -> TrackIdentity {
        var title = song.title
        var artist = song.artists.first?.name ?? ""
        if artist.isEmpty, let separator = title.range(of: " - ") {
            artist = String(title[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            title = String(title[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return TrackIdentity(
            videoId: song.videoId,
            title: TextMatch.queryTitle(title),
            artist: TextMatch.queryArtist(artist),
            album: song.album,
            durationSeconds: song.duration > 0 ? song.duration : nil
        )
    }
}
