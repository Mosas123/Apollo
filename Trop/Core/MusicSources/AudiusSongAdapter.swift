import Foundation

/// Only the queue transport is shared with YouTube. The namespaced ID is
/// decoded by PlaybackManager before touching any YouTube API.
extension MusicCatalogTrack {
    func asQueueSong() -> SongItem {
        SongItem(
            videoId: id.storageKey,
            title: title,
            artists: [YTArtist(name: artist, id: nil)],
            album: nil,
            albumId: nil,
            duration: durationSeconds,
            thumbnailUrl: artworkURL?.absoluteString,
            isExplicit: false,
            playlistId: nil,
            likeStatus: nil,
            contentKind: .music
        )
    }
}
