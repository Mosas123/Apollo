import Foundation

/// Apollo's own station engine. It builds a seed-based queue from Spotify's
/// catalogue, ranks it with local taste and diversifies the result. Audio is
/// resolved later by the normal playback pipeline.
actor StationService {
    static let shared = StationService()

    private struct Seed {
        let artistID: String
        let albumID: String?
        let trackID: String?
    }

    private struct Candidate {
        let song: SongItem
        let base: Double
        let popularity: Double
        let group: Group
        var reason: String = ""
    }

    private enum Group {
        case seedTop
        case album
        case related
        case search

        var base: Double {
            switch self {
            case .seedTop: return 1.0
            case .album: return 0.9
            case .related: return 0.8
            case .search: return 0.4
            }
        }

        var label: String {
            switch self {
            case .seedTop: return "artist"
            case .album: return "album"
            case .related: return "related"
            case .search: return "search"
            }
        }
    }

    private let source = SpotifyStationSource()
    private let taste = RadioTasteStore.shared
    private let lastFM = LastFMDiscoveryClient()
    private let embeddings = CatalogEmbeddingStore.shared
    private let learning = RadioLearningStore.shared
    private let bandit = RadioBanditStore.shared
    private var cache: [String: (songs: [SongItem], at: Date)] = [:]
    private let ttl: TimeInterval = 10 * 60

    func radio(for song: SongItem, options: RadioOptions) async -> [SongItem] {
        let key = cacheKey(song: song, options: options)
        if let cached = cache[key], Date().timeIntervalSince(cached.at) < ttl {
            return cached.songs
        }

        let startedAt = Date()
        var candidates: [Candidate] = []
        if let seed = await resolveSeed(song) {
            candidates = await candidatePool(seed: seed, seedSong: song, options: options)
        }

        let candidateCount = candidates.count
        var sourceMix: [String: Int] = [:]
        for candidate in candidates {
            sourceMix[candidate.group.label, default: 0] += 1
        }

        var ranked = await rank(candidates, seedSong: song, options: options)
        if ranked.isEmpty {
            ranked = await fallbackSearch(song: song, options: options)
        }

        let artistCounts = Dictionary(
            grouping: ranked.compactMap { $0.artists.first?.name },
            by: { TextMatch.normalizeArtist($0) }
        ).mapValues(\.count)
        let albumNames = Set(ranked.compactMap { $0.album.map(TextMatch.normalizeTitle) })

        let metric = RadioStationMetric(
            id: UUID(),
            date: Date(),
            seedTitle: song.title,
            style: options.style.rawValue,
            candidateCount: candidateCount,
            selectedCount: ranked.count,
            uniqueArtists: artistCounts.count,
            uniqueAlbums: albumNames.count,
            maxArtistRepeat: artistCounts.values.max() ?? 0,
            sourceMix: sourceMix,
            latencyMS: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
        await RadioMetricsStore.shared.record(metric)

        cache[key] = (ranked, Date())
        return ranked
    }

    // MARK: - Seed

    private func resolveSeed(_ song: SongItem) async -> Seed? {
        var trackID: String?
        if let catalog = song.catalogID, catalog.hasPrefix("spotify:track:") {
            trackID = SpotifyCatalogID.rawID(catalog)
        } else if song.videoId.hasPrefix("spotify:track:") {
            trackID = SpotifyCatalogID.rawID(song.videoId)
        }

        var albumID: String?
        if let album = song.albumId, album.hasPrefix("spotify:album:") {
            albumID = SpotifyCatalogID.rawID(album)
        }

        var artistID: String?
        if let artist = song.artists.first(where: { $0.id?.hasPrefix("spotify:artist:") == true }),
           let id = artist.id {
            artistID = SpotifyCatalogID.rawID(id)
        }

        if artistID == nil {
            let artistName = song.artists.first?.name ?? ""
            let query = [song.title, artistName].filter { !$0.isEmpty }.joined(separator: " ")
            if !query.isEmpty,
               let results = try? await SpotifyCatalogProvider().search(query, limit: 5) {
                let wanted = TextMatch.normalizeArtist(artistName)
                if !wanted.isEmpty,
                   let exact = results.artists.first(where: { TextMatch.normalizeArtist($0.name) == wanted }) {
                    artistID = exact.id
                } else if let track = results.tracks.first {
                    artistID = track.artists.first?.id
                    albumID = track.album?.id
                    if trackID == nil { trackID = track.id }
                } else if let artist = results.artists.first {
                    artistID = artist.id
                }
            }
        }

        guard let artistID, !artistID.isEmpty else { return nil }
        return Seed(artistID: artistID, albumID: albumID, trackID: trackID)
    }

    // MARK: - Candidates

    private func candidatePool(seed: Seed, seedSong: SongItem, options: RadioOptions) async -> [Candidate] {
        guard let snapshot = try? await source.snapshot(artistID: seed.artistID) else { return [] }

        var candidates: [Candidate] = []
        let style = options.style

        let seedTopLimit = style == .variety ? 6 : 10
        let seedTopBase = style == .variety ? 0.75 : 1.0
        let top = snapshot.topTracks.enumerated()
        for (index, song) in top.prefix(seedTopLimit) {
            if style == .deepCuts, index < 2 { continue }
            candidates.append(Candidate(
                song: song,
                base: seedTopBase,
                popularity: popularity(index: index, count: max(snapshot.topTracks.count, 1)),
                group: .seedTop,
                reason: "More from \(snapshot.artist.name)"
            ))
        }

        if let albumID = seed.albumID,
           let album = try? await SpotifyDetailService.shared.albumDetail(id: albumID) {
            let albumBase = style == .variety ? 0.45 : (style == .deepCuts ? 1.0 : 0.9)
            for (index, song) in album.songs.prefix(15).enumerated() {
                candidates.append(Candidate(
                    song: song,
                    base: albumBase,
                    popularity: popularity(index: index, count: max(album.songs.count, 1)),
                    group: .album,
                    reason: "From \(album.title)"
                ))
            }
        }

        let relatedLimit = style == .variety ? 5 : (style == .deepCuts ? 2 : 3)
        let related = Array(snapshot.related.prefix(relatedLimit))
        let relatedSnapshots = await relatedSnapshots(related, source: source)

        for (rank, relatedSnapshot) in relatedSnapshots {
            let base = (style == .variety ? 0.7 : (style == .deepCuts ? 0.85 : 0.8))
                - Double(rank) * 0.05
            for (index, song) in relatedSnapshot.topTracks.prefix(10).enumerated() {
                candidates.append(Candidate(
                    song: song,
                    base: base,
                    popularity: popularity(index: index, count: max(relatedSnapshot.topTracks.count, 1)),
                    group: .related,
                    reason: "Similar to \(relatedSnapshot.artist.name)"
                ))
            }
        }

        // Genre continuity: Last.fm tags of the seed artist are searched in
        // Spotify so a salsa station keeps serving salsa, not just one artist.
        let seedArtistName = seedSong.artists.first?.name ?? snapshot.artist.name
        let tags = await lastFM.topTags(artist: seedArtistName, limit: 6)
        for tag in tags.prefix(2) {
            let searchTerm = tag.name
            guard let results = try? await SpotifyCatalogProvider().search(searchTerm, limit: 12) else {
                continue
            }
            for track in results.tracks.prefix(8) {
                candidates.append(Candidate(
                    song: SpotifyCatalogMapper.song(from: track),
                    base: 0.68,
                    popularity: 0.5,
                    group: .related,
                    reason: "\(tag.name.capitalized) · same genre"
                ))
            }
        }

        let similarTracks = await lastFM.similarTracks(
            title: seedSong.title,
            artist: seedSong.artists.first?.name ?? "",
            limit: 10
        )
        for (index, match) in similarTracks.prefix(5).enumerated() {
            let query = "\(match.title) \(match.artist)"
            guard let results = try? await SpotifyCatalogProvider().search(query, limit: 2) else { continue }
            let normalizedTitle = TextMatch.normalizeTitle(match.title)
            guard let track = results.tracks.first(where: {
                TextMatch.normalizeTitle($0.title) == normalizedTitle
            }) ?? results.tracks.first else { continue }
            candidates.append(Candidate(
                song: SpotifyCatalogMapper.song(from: track),
                base: 0.72 - Double(index) * 0.03,
                popularity: min(max(match.match / 100, 0), 1),
                group: .related,
                reason: "Discovered via Last.fm"
            ))
        }

        let relatedNames = Set(
            snapshot.related.map { TextMatch.normalizeArtist($0.name) }
                + [TextMatch.normalizeArtist(snapshot.artist.name)]
        )
        let additionalArtists = await lastFM.similarArtists(
            name: snapshot.artist.name,
            limit: 8
        )
        var addedArtists = 0
        for match in additionalArtists where addedArtists < 2 {
            let name = TextMatch.normalizeArtist(match.name)
            guard !relatedNames.contains(name) else { continue }
            guard let results = try? await SpotifyCatalogProvider().search(match.name, limit: 3),
                  let artist = results.artists.first(where: {
                      TextMatch.normalizeArtist($0.name) == name
                  }),
                  let relatedSnapshot = try? await source.snapshot(artistID: artist.id) else {
                continue
            }
            for (index, song) in relatedSnapshot.topTracks.prefix(8).enumerated() {
                candidates.append(Candidate(
                    song: song,
                    base: 0.7 - Double(index) * 0.02,
                    popularity: popularity(index: index, count: max(relatedSnapshot.topTracks.count, 1)),
                    group: .related,
                    reason: "Similar to \(snapshot.artist.name)"
                ))
            }
            addedArtists += 1
        }

        return candidates.filter { !isSeed($0.song, seedSong: seedSong, seedTrackID: seed.trackID) }
    }

    private func relatedSnapshots(
        _ artists: [CatalogArtist],
        source: SpotifyStationSource
    ) async -> [(Int, SpotifyStationSnapshot)] {
        await withTaskGroup(of: (Int, SpotifyStationSnapshot?).self) { group in
            for (index, artist) in artists.enumerated() {
                group.addTask {
                    (index, try? await source.snapshot(artistID: artist.id))
                }
            }
            var result: [(Int, SpotifyStationSnapshot)] = []
            for await (index, snapshot) in group {
                if let snapshot { result.append((index, snapshot)) }
            }
            return result.sorted { $0.0 < $1.0 }
        }
    }

    private func isSeed(_ candidate: SongItem, seedSong: SongItem, seedTrackID: String?) -> Bool {
        if let seedTrackID,
           let raw = candidate.catalogID.flatMap(SpotifyCatalogID.rawID),
           raw == seedTrackID {
            return true
        }
        let title = TextMatch.normalizeTitle(candidate.title)
        let seedTitle = TextMatch.normalizeTitle(seedSong.title)
        let artist = candidate.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""
        let seedArtist = seedSong.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""
        return title == seedTitle
            && artist == seedArtist
            && abs(candidate.duration - seedSong.duration) <= 2
    }

    // MARK: - Ranking

    private func rank(
        _ candidates: [Candidate],
        seedSong: SongItem,
        options: RadioOptions
    ) async -> [SongItem] {
        _ = await taste.snapshot()
        let seedText = CatalogEmbeddingStore.text(for: seedSong)
        let weights = await learning.weights(for: options.style.rawValue)
        let style = options.style.rawValue
        let artistMultiplier = await bandit.multiplier(style: style, source: "artist")
        let albumMultiplier = await bandit.multiplier(style: style, source: "album")
        let relatedMultiplier = await bandit.multiplier(style: style, source: "related")
        let searchMultiplier = await bandit.multiplier(style: style, source: "search")
        let banditMultipliers: [String: Double] = [
            "artist": artistMultiplier,
            "album": albumMultiplier,
            "related": relatedMultiplier,
            "search": searchMultiplier
        ]
        let session = await MainActor.run {
            let recent = NowPlaying.shared.queueSongs.suffix(6)
            var artists = Set<String>()
            var albums = Set<String>()
            for song in recent {
                if let artist = song.artists.first?.name {
                    artists.insert(TextMatch.normalizeArtist(artist))
                }
                if let album = song.album { albums.insert(TextMatch.normalizeTitle(album)) }
            }
            return (artists, albums)
        }

        var seen = Set<String>()
        var scored: [(SongItem, Double, String, String, String, RadioFeatureVector, String)] = []

        for candidate in candidates {
            if !options.allowExplicit, candidate.song.isExplicit == true { continue }

            let identity = "\(TextMatch.normalizeTitle(candidate.song.title))|"
                + "\(candidate.song.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? "")|"
                + "\(candidate.song.duration / 2)"
            guard seen.insert(identity).inserted else { continue }

            let affinity = await taste.affinity(for: candidate.song.artists)
            let recent = await taste.isRecent(title: candidate.song.title, artists: candidate.song.artists)
            let artistNames = candidate.song.artists.map(\.name)
            let profile = await MainActor.run {
                TasteProfileStore.shared.signals(for: artistNames)
            }
            guard profile.skips < 5 else { continue }

            let candidateText = CatalogEmbeddingStore.text(for: candidate.song)
            let rawSimilarity = await embeddings.similarity(seedText, candidateText)
            let embeddingSimilarity = rawSimilarity.map { ($0 + 1) / 2 } ?? 0

            var isSeedTop = 0.0
            var isAlbum = 0.0
            var isRelated = 0.0
            var isSearch = 0.0
            switch candidate.group {
            case .seedTop: isSeedTop = 1
            case .album: isAlbum = 1
            case .related: isRelated = 1
            case .search: isSearch = 1
            }

            let features = RadioFeatureVector(values: [
                1,
                affinity,
                min(max(profile.weight / 12, 0), 1),
                candidate.popularity,
                recent ? 0 : 1,
                embeddingSimilarity,
                isSeedTop,
                isAlbum,
                isRelated,
                isSearch,
                min(Double(profile.skips) / 5, 1)
            ])

            var score = weights.score(features)
            score *= banditMultipliers[candidate.group.label] ?? 1
            score += Double.random(in: 0...0.01)

            let artistKey = candidate.song.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""
            let albumKey = TextMatch.normalizeTitle(candidate.song.album ?? "")
            if !artistKey.isEmpty, session.0.contains(artistKey) { score += 0.12 }
            if !albumKey.isEmpty, session.1.contains(albumKey) { score += 0.05 }
            scored.append((candidate.song, score, artistKey, albumKey, candidate.reason, features, candidate.group.label))
        }

        scored.sort { $0.1 > $1.1 }

        let defaultArtistCap = options.style == .variety ? 1 : (options.style == .deepCuts ? 2 : 3)
        let defaultAlbumCap = options.style == .variety ? 1 : 2
        let maxPerArtist = options.maxPerArtist > 0 ? options.maxPerArtist : defaultArtistCap
        let maxPerAlbum = options.maxPerAlbum > 0 ? options.maxPerAlbum : defaultAlbumCap

        var artistCounts: [String: Int] = [:]
        var albumCounts: [String: Int] = [:]
        var result: [SongItem] = []

        for (song, _, artistKey, albumKey, reason, features, source) in scored {
            guard result.count < options.limit else { break }
            if !artistKey.isEmpty, (artistCounts[artistKey] ?? 0) >= maxPerArtist { continue }
            if !albumKey.isEmpty, (albumCounts[albumKey] ?? 0) >= maxPerAlbum { continue }

            var stamped = song
            stamped.stationReason = reason
            result.append(stamped)

            await learning.snapshot(
                key: stamped.catalogID ?? stamped.videoId,
                style: options.style.rawValue,
                source: source,
                features: features
            )
            if !artistKey.isEmpty { artistCounts[artistKey, default: 0] += 1 }
            if !albumKey.isEmpty { albumCounts[albumKey, default: 0] += 1 }
        }

        return result
    }

    private func popularity(index: Int, count: Int) -> Double {
        guard count > 1 else { return 1 }
        return max(0, 1 - Double(index) / Double(count - 1))
    }

    // MARK: - Fallback

    private func fallbackSearch(song: SongItem, options: RadioOptions) async -> [SongItem] {
        let query = [song.title, song.artists.first?.name ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty,
              let results = try? await SpotifyCatalogProvider().search(query, limit: max(options.limit, 10)) else {
            return []
        }

        var seen = Set<String>()
        var songs: [SongItem] = []
        for track in results.tracks {
            if !options.allowExplicit, track.isExplicit { continue }
            var item = SpotifyCatalogMapper.song(from: track)
            item.stationReason = "Related to \(song.title)"
            let key = "\(TextMatch.normalizeTitle(item.title))|\(item.duration / 2)"
            guard seen.insert(key).inserted, !isSeed(item, seedSong: song, seedTrackID: nil) else { continue }
            songs.append(item)
            if songs.count >= options.limit { break }
        }
        return songs
    }

    private func cacheKey(song: SongItem, options: RadioOptions) -> String {
        "\(song.catalogID ?? song.videoId)|\(options.style.rawValue)|\(options.limit)|\(options.allowExplicit)"
    }
}
