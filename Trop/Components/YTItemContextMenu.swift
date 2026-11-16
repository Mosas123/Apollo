import SwiftUI

/// Long-press menu that adapts to what is being pressed: a song, an album,
/// an artist, a playlist or a podcast.
struct YTItemContextMenu: View {
    let item: YTItem

    var body: some View {
        switch item {
        case .song(let song):
            SongContextMenuButtons(song: song)
        case .episode(let episode):
            SongContextMenuButtons(song: episode.toSongItem())
        case .album(let album):
            AlbumContextMenu(album: album)
        case .artist(let artist):
            Button {
                AppRouter.shared.open(.artist(browseId: artist.browseId))
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        case .playlist(let playlist):
            Button {
                AppRouter.shared.open(.playlist(playlistId: playlist.id))
            } label: {
                Label("Open Playlist", systemImage: "music.note.list")
            }
        case .podcast(let podcast):
            Button {
                AppRouter.shared.open(.podcast(browseId: podcast.browseId))
            } label: {
                Label("Open Podcast", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }
}

/// Song actions shared by row and card long-press menus.
struct SongContextMenuButtons: View {
    let song: SongItem

    var body: some View {
        Button {
            PlaybackQueue.play([song], log: Log.homeScreenView, context: "Context play")
        } label: {
            Label("Play", systemImage: "play")
        }

        Button {
            let np = NowPlaying.shared
            let index = min(np.queueIndex + 1, np.queueSongs.count)
            np.queueSongs.insert(song, at: index)
            np.repairQueueIndex()
            np.persistQueueState()
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            NowPlaying.shared.queueSongs.append(song)
            NowPlaying.shared.persistQueueState()
        } label: {
            Label("Play After", systemImage: "text.line.last.and.arrowtriangle.forward")
        }

        Button {
            Task { await LikeStore.shared.toggle(song: song) }
        } label: {
            Label(
                LikeStore.shared.isLiked(videoId: song.videoId) ? "Unfavorite" : "Favorite",
                systemImage: LikeStore.shared.isLiked(videoId: song.videoId) ? "heart.fill" : "heart"
            )
        }

        if let artistId = song.artists.first(where: { $0.id != nil })?.id {
            Button {
                AppRouter.shared.open(.artist(browseId: artistId))
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }

        if let albumId = song.albumId, !albumId.isEmpty {
            Button {
                AppRouter.shared.open(.album(browseId: albumId))
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }

        if MusicPlaybackIdentity.isYouTube(song.videoId) {
            Button {
                PlaybackQueue.startRadio(for: song)
            } label: {
                Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
            }
        }

        if let url = URL(string: song.webUrl) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}
