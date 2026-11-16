import Foundation

/// Picks recommendations for the Home shelves: AI first when it is configured,
/// otherwise the on-device taste profile (local discovery).
@MainActor
enum DiscoveryService {
    static func songs() async -> [SongItem] {
        let ai = await ForYouService.musicSongs()
        if !ai.isEmpty { return ai }
        return await SurpriseMeService.musicQueue(seedVideoId: NowPlaying.shared.videoId)
    }

    static func artists() async -> [ArtistItem] {
        let ai = await ForYouService.artists()
        if !ai.isEmpty { return ai }
        return await LocalDiscoveryService.artists()
    }

    static func podcasts() async -> [YTItem] {
        let ai = await ForYouService.podcasts()
        if !ai.isEmpty { return ai }
        return await LocalDiscoveryService.podcasts()
    }
}
