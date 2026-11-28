import SwiftUI

/// One catalogue lookup policy for song rows and the player. Never interpret
/// an arbitrary subtitle (duration, playlist name, etc.) as an album search.
struct SongArtworkView: View {
    let song: SongItem
    var onMetadataResolved: ((ResolvedMetadata) -> Void)? = nil

    @State private var resolvedURL: String?
    @State private var resolvedKey: String?

    private var taskKey: String {
        "\(song.videoId)|\(song.title)|\(song.artists.map(\.name).joined(separator: ", "))|\(song.album ?? "")|\(song.duration)"
    }

    private var needsVerifiedCover: Bool {
        song.contentKind == .podcast || song.contentKind == .episode
            || MusicPlaybackIdentity.isExternal(song.videoId)
            || MusicArtworkSelectionPolicy.shouldResolveVerifiedCover(
                thumbnailURL: song.thumbnailUrl,
                isVideo: song.isVideo,
                musicVideoType: song.musicVideoType
            )
    }

    var body: some View {
        GeometryReader { geometry in
            if !needsVerifiedCover, let sourceCover = song.thumbnailUrl,
               !sourceCover.isEmpty {
                // Known release art is stable across the row and full player.
                AsyncImageView(url: sourceCover)
            } else if resolvedKey == taskKey, let resolvedURL {
                AsyncImageView(url: resolvedURL)
            } else {
                // Never borrow the player's global image: pressing a track must
                // not rewrite another row's artwork. This row resolves its own.
                AsyncImageView(url: song.thumbnailUrl)
            }
        }
            .task(id: taskKey) {
                resolvedURL = nil
                resolvedKey = taskKey
                if song.contentKind == .episode || song.contentKind == .podcast {
                    // Every episode must show the official show cover, even
                    // when the row has a video frame or a missing thumbnail.
                    let show = song.artists.first?.name ?? song.title
                    guard !show.isEmpty else { return }
                    let artwork = await PodcastAudioResolver.shared.artwork(for: show)
                    guard !Task.isCancelled else { return }
                    resolvedURL = artwork?.absoluteString
                    return
                }
                guard needsVerifiedCover,
                      song.contentKind == nil || song.contentKind == .music else { return }
                // Same subject and cache as the player, so the row and the
                // playing view eventually show the exact same image.
                let subject = ArtworkSubject.track(
                    title: song.title,
                    artist: song.artists.map(\.name).joined(separator: ", "),
                    album: song.album,
                    duration: song.duration
                )
                let cover = await ArtworkResolver.upgrade(subject)
                guard !Task.isCancelled else { return }
                resolvedURL = cover?.absoluteString
            }
    }
}

extension SongArtworkView {
    /// Saved-library rows store `SongEntity`; map it to the player item shape.
    init(song entity: SongEntity, onMetadataResolved: ((ResolvedMetadata) -> Void)? = nil) {
        self.init(
            song: SongItem(
                videoId: entity.id,
                title: entity.title,
                artists: entity.artistName.map { [YTArtist(name: $0, id: nil)] } ?? [],
                album: entity.albumName,
                albumId: nil,
                duration: entity.duration,
                thumbnailUrl: entity.thumbnailUrl,
                isExplicit: false,
                playlistId: nil,
                likeStatus: nil
            ),
            onMetadataResolved: onMetadataResolved
        )
    }
}
