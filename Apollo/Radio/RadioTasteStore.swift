import Foundation

/// Local taste signal for the station ranker. Derives artist affinity and
/// recent-history penalties from the local DB; no network calls.
actor RadioTasteStore {
    static let shared = RadioTasteStore()

    struct Snapshot {
        var artistAffinity: [String: Double] = [:]
        var recentKeys: Set<String> = []
        var recentArtists: Set<String> = []
    }

    private var cached: Snapshot?
    private var cachedAt: Date?
    private let ttl: TimeInterval = 5 * 60

    func snapshot() async -> Snapshot {
        if let cached, let cachedAt, Date().timeIntervalSince(cachedAt) < ttl {
            return cached
        }
        let built = await build()
        cached = built
        cachedAt = Date()
        return built
    }

    func affinity(for artists: [YTArtist]) -> Double {
        guard let snapshot = cached else { return 0 }
        var best = 0.0
        for artist in artists {
            let key = TextMatch.normalizeArtist(artist.name)
            best = max(best, snapshot.artistAffinity[key] ?? 0)
        }
        return best
    }

    func isRecent(title: String, artists: [YTArtist]) -> Bool {
        guard let snapshot = cached else { return false }
        return snapshot.recentKeys.contains(key(title: title, artists: artists))
    }

    func isRecentArtist(_ artists: [YTArtist]) -> Bool {
        guard let snapshot = cached else { return false }
        return artists.contains {
            snapshot.recentArtists.contains(TextMatch.normalizeArtist($0.name))
        }
    }

    private func key(title: String, artists: [YTArtist]) -> String {
        let artist = artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""
        return "\(TextMatch.normalizeTitle(title))|\(artist)"
    }

    private func build() async -> Snapshot {
        let db = DatabaseService.shared
        let songs = (try? await db.fetchAll(SongEntity.self)) ?? []
        let artists = (try? await db.fetchAll(ArtistEntity.self)) ?? []
        let events = (try? await db.fetchAll(Event.self)) ?? []

        let songsByID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        var affinity: [String: Double] = [:]

        for song in songs {
            let names = artistKeys(song.artistName)
            var weight = song.liked ? 2.0 : 0.0
            if song.inLibrary != nil { weight += 0.5 }
            weight += min(2.5, log1p(Double(max(song.totalPlayTime, 0)) / 60_000))
            guard weight > 0 else { continue }
            for name in names { affinity[name, default: 0] += weight }
        }

        for artist in artists where artist.bookmarkedAt != nil {
            let name = TextMatch.normalizeArtist(artist.name)
            affinity[name, default: 0] += 3
        }

        let recentCutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        var recentKeys = Set<String>()
        var recentArtists = Set<String>()

        for event in events {
            guard event.timestamp >= recentCutoff,
                  let song = songsByID[event.songId] else { continue }
            let names = artistKeys(song.artistName)
            let primary = names.first ?? ""
            recentKeys.insert("\(TextMatch.normalizeTitle(song.title))|\(primary)")
            recentArtists.formUnion(names)
        }

        let eventSignals = await PlaybackEventStore.shared.artistSignals(since: recentCutoff)
        for (artist, signal) in eventSignals {
            let key = TextMatch.normalizeArtist(artist)
            guard !key.isEmpty else { continue }
            let delta = Double(signal.completed) * 0.8
                + Double(signal.saved) * 1.5
                - Double(signal.skipped) * 0.5
            affinity[key, default: 0] += max(-2, min(4, delta))
            if signal.lastPlayed.map({ $0 >= recentCutoff }) == true {
                recentArtists.insert(key)
            }
        }

        let maxAffinity = affinity.values.max() ?? 0
        if maxAffinity > 0 {
            affinity = affinity.mapValues { $0 / maxAffinity }
        }

        return Snapshot(
            artistAffinity: affinity,
            recentKeys: recentKeys,
            recentArtists: recentArtists
        )
    }

    private func artistKeys(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value
            .components(separatedBy: ",")
            .map { TextMatch.normalizeArtist($0) }
            .filter { !$0.isEmpty }
    }
}
