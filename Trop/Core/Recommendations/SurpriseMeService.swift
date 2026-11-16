import Foundation

/// "Surprise me": when the listener can't decide, pick something for them.
/// Music comes from the library (falling back to AI/For You picks); podcasts
/// and audiobooks come from the active category feed.
@MainActor
enum SurpriseMeService {
    static func musicSong(currentVideoId: String?) async -> SongItem? {
        if let liked = try? await DatabaseService.shared.fetchAllLikedSongs(), !liked.isEmpty {
            let pool = liked.filter { $0.id != currentVideoId }
            if let pick = pool.randomElement() {
                return SongItem(entity: pick)
            }
        }
        let forYou = await ForYouService.musicSongs()
        return forYou.filter { $0.videoId != currentVideoId }.randomElement()
    }

    static func episode(from sections: [HomePage.Section]) -> SongItem? {
        let episodes = sections.flatMap(\.items).compactMap { item -> SongItem? in
            if case .episode(let episode) = item { return episode.toSongItem() }
            return nil
        }
        return episodes.randomElement()
    }

    static func audiobook(from sections: [HomePage.Section]) -> AlbumItem? {
        let books = sections.flatMap(\.items).compactMap { item -> AlbumItem? in
            if case .album(let album) = item, album.isAudiobook { return album }
            return nil
        }
        return books.randomElement()
    }
}
