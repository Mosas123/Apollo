import Foundation

/// Phase 4: blend another catalogue into Apollo's discovery without giving it
/// audio. Apple charts provide editorial movement; each entry is resolved to
/// a Spotify catalogue object so playback/quality stay on our existing paths.
@MainActor
enum CombinedDiscoveryService {
    private static var cache: [String: (sections: [ExploreSection], at: Date)] = [:]
    private static let ttl: TimeInterval = 6 * 60 * 60

    static func appleChartSections(limit: Int = 6) async -> [ExploreSection] {
        let storefront = SettingsStore.shared.contentCountry
        let country = storefront.isEmpty ? "us" : storefront.lowercased()
        let key = "\(country)|\(limit)"

        if let cached = cache[key], Date().timeIntervalSince(cached.at) < ttl {
            return cached.sections
        }

        async let songsTask = appleSections(kind: .songs, country: country, limit: limit)
        async let albumsTask = appleSections(kind: .albums, country: country, limit: limit)
        let (songs, albums) = await (songsTask, albumsTask)
        let sections = [songs, albums].compactMap { $0 }
        cache[key] = (sections, Date())
        return sections
    }

    private static func appleSections(
        kind: AppleChartKind,
        country: String,
        limit: Int
    ) async -> ExploreSection? {
        let charts = await AppleChartsClient().top(kind: kind, country: country, limit: limit)
        guard !charts.isEmpty else { return nil }

        var items: [YTItem] = []
        var seen = Set<String>()

        for chart in charts {
            let query = "\(chart.title) \(chart.artist)"
            guard let results = try? await SpotifyCatalogProvider().search(query, limit: 3) else { continue }

            let spotifyItem: YTItem?
            switch kind {
            case .songs:
                let track = results.tracks.first {
                    TextMatch.normalizeTitle($0.title) == TextMatch.normalizeTitle(chart.title)
                } ?? results.tracks.first
                spotifyItem = track.map { .song(SpotifyCatalogMapper.song(from: $0)) }
            case .albums:
                let album = results.albums.first {
                    TextMatch.normalizeTitle($0.title) == TextMatch.normalizeTitle(chart.title)
                } ?? results.albums.first
                spotifyItem = album.map { .album(SpotifyCatalogMapper.album(from: $0)) }
            }

            guard let spotifyItem, seen.insert(spotifyItem.id).inserted else { continue }
            items.append(spotifyItem)
        }

        guard !items.isEmpty else { return nil }
        let title = kind == .songs ? "Apple Music · Top Songs" : "Apple Music · Top Albums"
        return ExploreSection(title: title, kind: .cards, items: items, moods: [])
    }
}
