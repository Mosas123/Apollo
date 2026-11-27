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
    }

    private let source = SpotifyStationSource()
    private let taste = RadioTasteStore.shared
    private var cache: [String: (songs: [SongItem], at: Date)] = [:]
    private let ttl: TimeInterval = 10 * 60

    func radio(for song: SongItem, options: RadioOptions) async -> [SongItem] {
        let key = cacheKey(song: song, options: options)
        if let cached = cache[key], Date().timeIntervalSince(cached.at) < ttl {
            return cached.songs
        }

        var candidates: [Candidate] = []
        if let seed = await resolveSeed(song) {
            candidates = await candidatePool(seed: seed, seedSong: song, options: options)
        }

        var ranked = await rank(candidates, seedSong: song, options: options)
        if ranked.isEmpty {
            ranked = await fallbackSearch(song: song, options: options)
        }

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
                group: .seedTop
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
                    group: .album
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
                    group: .related
                ))
            }
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

        var seen = Set<String>()
        var scored: [(SongItem, Double, String, String)] = []

        for candidate in candidates {
            if !options.allowExplicit, candidate.song.isExplicit == true { continue }

            let identity = "\(TextMatch.normalizeTitle(candidate.song.title))|"
                + "\(candidate.song.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? "")|"
                + "\(candidate.song.duration / 2)"
            guard seen.insert(identity).inserted else { continue }

            let affinity = await taste.affinity(for: candidate.song.artists)
            let recent = await taste.isRecent(title: candidate.song.title, artists: candidate.song.artists)

            var score = candidate.base
            score += 0.30 * affinity
            score += 0.12 * candidate.popularity
            score += recent ? -0.18 : 0.04

            switch options.style {
            case .similar:
                if case .seedTop = candidate.group { score += 0.05 }
            case .variety:
                if case .seedTop = candidate.group { score -= 0.15 }
                if case .related = candidate.group { score += 0.08 }
                score += 0.08 * affinity
            case .deepCuts:
                if case .album = candidate.group { score += 0.10 }
                if case .related = candidate.group { score += 0.06 }
                score -= 0.06 * candidate.popularity
            }

            score += Double.random(in: 0...0.02)

            let artistKey = candidate.song.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""
            let albumKey = TextMatch.normalizeTitle(candidate.song.album ?? "")
            scored.append((candidate.song, score, artistKey, albumKey))
        }

        scored.sort { $0.1 > $1.1 }

        let maxPerArtist = options.style == .variety ? 1 : (options.style == .deepCuts ? 2 : 3)
        let maxPerAlbum = options.style == .variety ? 1 : 2

        var artistCounts: [String: Int] = [:]
        var albumCounts: [String: Int] = [:]
        var result: [SongItem] = []

        for (song, _, artistKey, albumKey) in scored {
            guard result.count < options.limit else { break }
            if !artistKey.isEmpty, (artistCounts[artistKey] ?? 0) >= maxPerArtist { continue }
            if !albumKey.isEmpty, (albumCounts[albumKey] ?? 0) >= maxPerAlbum { continue }

            result.append(song)
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
            let item = SpotifyCatalogMapper.song(from: track)
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
