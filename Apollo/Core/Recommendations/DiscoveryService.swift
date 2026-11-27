import Foundation

/// Picks recommendations for the Home shelves: AI first when it is configured,
/// otherwise the on-device taste profile (local discovery). Results are cached
/// briefly so Home doesn't refetch on every appearance.
@MainActor
enum DiscoveryService {
    private static var cachedSongs: (date: Date, items: [SongItem])?
    private static var cachedArtists: (date: Date, items: [ArtistItem])?
    private static var cachedPodcasts: (date: Date, items: [YTItem])?
    private static let ttl: TimeInterval = 30 * 60

    static func songs(force: Bool = false) async -> [SongItem] {
        if !force, let cached = cachedSongs, Date().timeIntervalSince(cached.date) < ttl {
            return cached.items
        }
        let ai = await ForYouService.musicSongs()
        let items = ai.isEmpty
            ? await SurpriseMeService.musicQueue(seedVideoId: NowPlaying.shared.videoId)
            : ai
        if !items.isEmpty { cachedSongs = (Date(), items) }
        return items
    }

    static func artists(force: Bool = false) async -> [ArtistItem] {
        if !force, let cached = cachedArtists, Date().timeIntervalSince(cached.date) < ttl {
            return cached.items
        }
        let ai = await ForYouService.artists()
        let items = ai.isEmpty ? await LocalDiscoveryService.artists() : ai
        if !items.isEmpty { cachedArtists = (Date(), items) }
        return items
    }

    static func podcasts(force: Bool = false) async -> [YTItem] {
        if !force, let cached = cachedPodcasts, Date().timeIntervalSince(cached.date) < ttl {
            return cached.items
        }
        let ai = await ForYouService.podcasts()
        let items = ai.isEmpty ? await LocalDiscoveryService.podcasts() : ai
        if !items.isEmpty { cachedPodcasts = (Date(), items) }
        return items
    }

    static func invalidate() {
        cachedSongs = nil
        cachedArtists = nil
        cachedPodcasts = nil
    }
}
