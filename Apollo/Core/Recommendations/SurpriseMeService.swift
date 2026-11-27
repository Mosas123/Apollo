import Foundation

/// "Surprise me": when the listener can't decide, pick something for them.
/// Mirrors the Surprise Me algorithm of the reference project: build a taste
/// profile, score candidates by affinity, keep a shortlist and pick at random
/// from it (so it varies), excluding what was just offered.
@MainActor
enum SurpriseMeService {
    /// A longer queue for a "Surprise me" session: AI picks first (when
    /// configured), then YouTube Music recommendations (radio) from a seed.
    /// Never just replays the user's library; the AI/radio keeps suggesting.
    static func musicQueue(
        seedVideoId: String?,
        excluding: String? = nil,
        refreshAI: Bool = false
    ) async -> [SongItem] {
        var items: [SongItem] = []
        var seen = Set<String>()

        // 1) AI picks, fresh on refill so it keeps learning from the profile.
        if AIProviderClient.configured() != nil {
            for song in await ForYouService.musicSongs(force: refreshAI) {
                guard song.videoId != excluding,
                      song.videoId != seedVideoId,
                      seen.insert(song.videoId).inserted else { continue }
                items.append(song)
            }
        }

        // 2) Apollo stations until ~30 songs.
        if items.count < 30 {
            for seed in await stationSeeds(preferred: seedVideoId, excluding: excluding) {
                let station = await StationService.shared.radio(for: seed, options: .default)
                for song in station {
                    guard song.videoId != excluding,
                          song.videoId != seed.videoId,
                          seen.insert(song.videoId).inserted else { continue }
                    items.append(song)
                    if items.count >= 30 { break }
                }
                if items.count >= 30 { break }
            }
        }

        // 3) Last resort: songs by the listener's learned artists and genres.
        if items.count < 8 {
            let queries = TasteProfileStore.shared.topArtists(limit: 4)
                + TasteProfileStore.shared.topGenres(limit: 2)
            for query in queries {
                guard let results = try? await SpotifyCatalogProvider().search(query, limit: 10) else { continue }
                let songs = results.tracks.map { SpotifyCatalogMapper.song(from: $0) }
                for song in songs where song.videoId != excluding && song.videoId != seedVideoId {
                    guard seen.insert(song.videoId).inserted else { continue }
                    items.append(song)
                    if items.count >= 15 { break }
                }
                if items.count >= 15 { break }
            }
        }

        return items
    }

    /// Top-played and liked songs act as station seeds (not as the queue itself).
    private static func stationSeeds(preferred: String?, excluding: String?) async -> [SongItem] {
        var seeds: [SongItem] = []
        var seen = Set<String>()

        if let preferred {
            let current = NowPlaying.shared.queueSongs.first {
                $0.videoId == preferred || $0.catalogID == preferred
            }
            if let current, seen.insert(current.videoId).inserted {
                seeds.append(current)
            } else if let entity = try? await DatabaseService.shared.fetchOne(SongEntity.self, key: preferred),
                      seen.insert(entity.id).inserted {
                seeds.append(SongItem(entity: entity))
            }
        }

        if seeds.count < 2 {
            let top = (try? await DatabaseService.shared.fetchTopSongs(limit: 10)) ?? []
            for entity in top.shuffled() where entity.id != excluding && seen.insert(entity.id).inserted {
                seeds.append(SongItem(entity: entity))
                if seeds.count >= 2 { break }
            }
        }

        if seeds.count < 2 {
            let liked = (try? await DatabaseService.shared.fetchAllLikedSongs()) ?? []
            for entity in liked.shuffled() where entity.id != excluding && seen.insert(entity.id).inserted {
                seeds.append(SongItem(entity: entity))
                if seeds.count >= 2 { break }
            }
        }

        return Array(seeds.prefix(2))
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

    static func audiobook(from sections: [HomeSection]) -> AlbumItem? {
        let books = sections.flatMap(\.items).compactMap { item -> AlbumItem? in
            if case .album(let album) = item, album.isAudiobook { return album }
            return nil
        }
        return books.randomElement()
    }
}
