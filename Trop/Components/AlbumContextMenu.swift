import SwiftUI

/// Album actions used by long-press menus on album cards.
@MainActor
enum AlbumActions {
    static func songs(for album: AlbumItem) async -> [SongItem] {
        guard let json = try? await InnerTubeClient.tropShared.browse(browseId: album.browseId).value else {
            return []
        }
        return AlbumDetailViewModel.parseAlbumDetail(from: json, browseId: album.browseId).songs
    }

    static func play(_ album: AlbumItem, shuffle: Bool) {
        Task {
            let songs = await songs(for: album)
            guard !songs.isEmpty else { return }
            if shuffle {
                PlaybackQueue.playShuffled(songs, log: Log.albumDetail, context: "Album shuffle")
            } else {
                PlaybackQueue.play(songs, log: Log.albumDetail, context: "Album")
            }
        }
    }

    static func playNext(_ album: AlbumItem) {
        Task {
            let songs = await songs(for: album)
            guard !songs.isEmpty else { return }
            let np = NowPlaying.shared
            let index = min(np.queueIndex + 1, np.queueSongs.count)
            np.queueSongs.insert(contentsOf: songs, at: index)
            np.repairQueueIndex()
            np.persistQueueState()
        }
    }

    static func playAfter(_ album: AlbumItem) {
        Task {
            let songs = await songs(for: album)
            guard !songs.isEmpty else { return }
            NowPlaying.shared.queueSongs.append(contentsOf: songs)
            NowPlaying.shared.persistQueueState()
        }
    }

    static func toggleSave(_ album: AlbumItem) {
        Task {
            let entity = try? await DatabaseService.shared.fetchOne(AlbumEntity.self, key: album.browseId)
            if entity?.bookmarkedAt != nil {
                try? await SyncBridge.mutations.unsaveAlbum(browseId: album.browseId)
            } else {
                try? await SyncBridge.mutations.saveAlbum(
                    browseId: album.browseId,
                    title: album.title,
                    thumbnailUrl: album.thumbnailUrl,
                    playlistId: album.playlistId,
                    songCount: 0,
                    duration: 0
                )
            }
        }
    }

    static func shareURL(for album: AlbumItem) -> URL? {
        if let playlistId = album.playlistId, !playlistId.isEmpty {
            return URL(string: "https://music.youtube.com/playlist?list=\(playlistId)")
        }
        return URL(string: "https://music.youtube.com/browse/\(album.browseId)")
    }
}

struct AlbumContextMenu: View {
    let album: AlbumItem

    var body: some View {
        Button { AlbumActions.play(album, shuffle: false) } label: {
            Label("Play", systemImage: "play")
        }
        Button { AlbumActions.play(album, shuffle: true) } label: {
            Label("Shuffle", systemImage: "shuffle")
        }
        Button { AlbumActions.playNext(album) } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button { AlbumActions.playAfter(album) } label: {
            Label("Play After", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
        Button { AlbumActions.toggleSave(album) } label: {
            Label("Save to Library", systemImage: "plus.circle")
        }
        if let artistId = album.artists.first(where: { $0.id != nil })?.id {
            Button { AppRouter.shared.open(.artist(browseId: artistId)) } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }
        if let url = AlbumActions.shareURL(for: album) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}
