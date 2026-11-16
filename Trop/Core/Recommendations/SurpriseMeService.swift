import Foundation

/// "Surprise me": when the listener can't decide, pick something for them.
/// Mirrors the Surprise Me algorithm of the reference project: build a taste
/// profile, score candidates by affinity, keep a shortlist and pick at random
/// from it (so it varies), excluding what was just offered.
@MainActor
enum SurpriseMeService {
    /// Random among this many of the best matches, so the pick varies.
    private static let shortlistSize = 12
    private static var recentlyOffered: [String] = []

    static func musicSong(currentVideoId: String?) async -> SongItem? {
        let liked = (try? await DatabaseService.shared.fetchAllLikedSongs()) ?? []
        let topArtists = (try? await DatabaseService.shared.fetchArtists(limit: 12))?.map(\.name) ?? []

        guard !liked.isEmpty else {
            // Nothing in the library yet: fall back to AI/For You picks.
            let forYou = await ForYouService.musicSongs()
            return forYou.filter { $0.videoId != currentVideoId }.randomElement()
        }

        // Taste profile: artists the listener keeps in their library weigh most,
        // then artists of liked songs.
        var artistWeight: [String: Double] = [:]
        for name in topArtists {
            artistWeight[name, default: 0] += 2
        }
        for song in liked {
            guard let artist = song.artistName, !artist.isEmpty else { continue }
            artistWeight[artist, default: 0] += 1
        }
        let strongest = artistWeight.values.max() ?? 1

        func score(_ song: SongEntity) -> Double {
            let weight = artistWeight[song.artistName ?? ""] ?? 0
            return weight / strongest
        }

        var pool = liked.filter {
            $0.id != currentVideoId && !recentlyOffered.contains($0.id)
        }
        if pool.isEmpty {
            pool = liked.filter { $0.id != currentVideoId }
        }

        let shortlist = pool.sorted { score($0) > score($1) }.prefix(shortlistSize)
        guard let pick = shortlist.randomElement() else { return nil }

        recentlyOffered.append(pick.id)
        if recentlyOffered.count > 20 {
            recentlyOffered.removeFirst()
        }
        return SongItem(entity: pick)
    }

    /// A longer, AI-assisted queue for a "Surprise me" session. AI picks come
    /// first (so the next songs reflect what it learned), then the library.
    static func musicQueue(currentVideoId: String?, refreshAI: Bool = false) async -> [SongItem] {
        var items: [SongItem] = []
        var seen = Set<String>()

        for song in await ForYouService.musicSongs(force: refreshAI) {
            guard song.videoId != currentVideoId, seen.insert(song.videoId).inserted else { continue }
            items.append(song)
        }

        let liked = (try? await DatabaseService.shared.fetchAllLikedSongs()) ?? []
        for entity in liked.shuffled() {
            let song = SongItem(entity: entity)
            guard song.videoId != currentVideoId, seen.insert(song.videoId).inserted else { continue }
            items.append(song)
            if items.count >= 30 { break }
        }
        return items
    }

    /// All episodes available in the current sections, deduped.
    static func episodes(from sections: [HomeSection]) -> [SongItem] {
        var seen = Set<String>()
        return sections.flatMap(\.items).compactMap { item -> SongItem? in
            guard case .episode(let episode) = item else { return nil }
            guard seen.insert(episode.videoId).inserted else { return nil }
            return episode.toSongItem()
        }
    }

    static func episode(from sections: [HomeSection]) -> SongItem? {
        let episodes = sections.flatMap(\.items).compactMap { item -> SongItem? in
            if case .episode(let episode) = item { return episode.toSongItem() }
            return nil
        }
        return episodes.randomElement()
    }

    static func audiobook(from sections: [HomeSection]) -> AlbumItem? {
        let books = sections.flatMap(\.items).compactMap { item -> AlbumItem? in
            if case .album(let album) = item, album.isAudiobook { return album }
            return nil
        }
        return books.randomElement()
    }
}
