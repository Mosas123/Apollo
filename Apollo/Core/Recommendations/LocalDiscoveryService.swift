import Foundation

/// Local recommendations from the learned taste profile — used when the AI is
/// off (or returns nothing). Artists come from YouTube Music's "related
/// artists"; podcasts from Podcast Index trending / iTunes, validated against
/// real YouTube Music episodes.
@MainActor
enum LocalDiscoveryService {
    // MARK: - Artists

    static func artists(limit: Int = 10) async -> [ArtistItem] {
        let seeds = await seedArtistNames()
        guard !seeds.isEmpty else { return [] }

        var results: [ArtistItem] = []
        var seen = Set<String>()
        let known = Set(seeds.map { $0.lowercased() })

        for name in seeds.prefix(3) {
            guard let seed = await resolveArtist(name),
                  let json = try? await InnerTubeClient.apolloShared.browse(browseId: seed.browseId).value else { continue }
            let detail = ArtistDetailViewModel.parseArtistDetail(from: json, browseId: seed.browseId)
            for related in detail.relatedArtists {
                guard !known.contains(related.name.lowercased()),
                      seen.insert(related.browseId).inserted else { continue }
                results.append(related)
                if results.count >= limit { return results }
            }
        }
        return results
    }

    private static func seedArtistNames() async -> [String] {
        var seeds = TasteProfileStore.shared.topArtists(limit: 6)
        if seeds.isEmpty {
            seeds = (try? await DatabaseService.shared.fetchArtists(limit: 6))?.map(\.name) ?? []
        }
        if seeds.isEmpty {
            let liked = (try? await DatabaseService.shared.fetchAllLikedSongs()) ?? []
            var seen = Set<String>()
            for song in liked {
                guard let artist = song.artistName, !artist.isEmpty,
                      seen.insert(artist).inserted else { continue }
                seeds.append(artist)
                if seeds.count >= 6 { break }
            }
        }
        return seeds
    }

    private static func resolveArtist(_ name: String) async -> ArtistItem? {
        guard !name.isEmpty, let raw = try? await SearchService.shared.search(query: name) else { return nil }
        for section in SearchParser.parseSearchResults(from: raw) {
            for item in section.items {
                if case .artist(let artist) = item { return artist }
            }
        }
        return nil
    }

    // MARK: - Podcasts

    static func podcasts(limit: Int = 8) async -> [YTItem] {
        let names = await podcastNames(limit: limit + 4)
        var items: [YTItem] = []
        var seen = Set<String>()

        for name in names {
            guard let raw = try? await SearchService.shared.search(query: name) else { continue }
            let episode = SearchParser.parseSearchResults(from: raw)
                .flatMap(\.items)
                .compactMap { item -> EpisodeItem? in
                    if case .episode(let episode) = item { return episode }
                    return nil
                }
                .first
            if let episode, seen.insert(episode.videoId).inserted {
                items.append(.episode(episode))
            }
            if items.count >= limit { break }
        }
        return items
    }

    private static func podcastNames(limit: Int) async -> [String] {
        if let client = PodcastIndexClient.fromSettings(),
           let feeds = try? await client.trending(max: 20) {
            let names = Array(feeds.compactMap(\.title).prefix(limit))
            if !names.isEmpty { return names }
        }

        // iTunes fallback, seeded by the taste profile plus broad topics.
        var terms = TasteProfileStore.shared.topArtists(limit: 2)
        terms += TasteProfileStore.shared.topGenres(limit: 3)
        terms += ["music", "culture", "comedy", "news"]

        var names: [String] = []
        var seen = Set<String>()
        for term in terms {
            let results = await iTunesPodcastNames(term: term, limit: 6)
            for name in results where seen.insert(name.lowercased()).inserted {
                names.append(name)
            }
            if names.count >= limit { break }
        }
        return names
    }

    private struct ITunesPodcastResponse: Decodable {
        struct Result: Decodable { let collectionName: String? }
        let results: [Result]?
    }

    private static func iTunesPodcastNames(term: String, limit: Int) async -> [String] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(ITunesPodcastResponse.self, from: data) else {
            return []
        }
        return (decoded.results ?? []).compactMap(\.collectionName).filter { !$0.isEmpty }
    }
}
