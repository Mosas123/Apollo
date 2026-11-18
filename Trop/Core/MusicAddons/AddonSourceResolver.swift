import Foundation

/// Finds the best addon stream for a song from its metadata. Shared by playback
/// upgrades and lossless downloads, so both use identical matching.
enum AddonSourceResolver {
    struct Match: Sendable {
        let track: AddonTrack
        let stream: AddonStream
    }

    private struct Criteria: Sendable {
        let title: String
        let artist: String
        let album: String?
        let duration: Int?
        let queries: [String]
    }

    /// Races the enabled addons instead of querying them one by one: whichever
    /// finds a lossless stream wins immediately, and the rest are cancelled.
    @MainActor
    static func bestMatch(for song: SongItem) async -> Match? {
        let installations = Array(MusicAddonsStore.shared.enabledStremioInstallations.prefix(4))
        guard !installations.isEmpty else { return nil }

        let title = TextMatch.queryTitle(song.title)
        let artist = TextMatch.queryArtist(song.artists.first?.name ?? "")
        // Two searches race per addon: the specific one (artist + album +
        // title) and the fallback (artist + title) for addons whose search
        // chokes on the extra album words.
        let album = TextMatch.queryTitle(song.album ?? "")
        var queries: [String] = []
        let withAlbum = [artist, album, title].filter { !$0.isEmpty }.joined(separator: " ")
        let withoutAlbum = [artist, title].filter { !$0.isEmpty }.joined(separator: " ")
        if !withAlbum.isEmpty { queries.append(withAlbum) }
        if !withoutAlbum.isEmpty, !queries.contains(withoutAlbum) { queries.append(withoutAlbum) }
        let criteria = Criteria(
            title: song.title,
            artist: artist,
            album: song.album,
            duration: song.duration > 0 ? song.duration : nil,
            queries: queries
        )

        return await withTaskGroup(of: (Match, Int)?.self) { group in
            for installation in installations {
                group.addTask { await bestMatch(in: installation, criteria: criteria) }
            }
            var best: (Match, Int)?
            for await candidate in group {
                guard let candidate else { continue }
                if best == nil || candidate.1 > best!.1 {
                    best = candidate
                }
                if candidate.1 == 3 {
                    group.cancelAll()
                    break
                }
            }
            return best?.0
        }
    }

    /// Races the queries of one addon too: the first lossless answer wins and
    /// the other query is cancelled.
    private static func bestMatch(
        in installation: MusicAddonInstallation,
        criteria: Criteria
    ) async -> (Match, Int)? {
        guard let client = try? MusicAddonClient(installation: installation) else { return nil }
        return await withTaskGroup(of: (Match, Int)?.self) { group in
            for query in criteria.queries {
                group.addTask { await bestMatch(in: client, query: query, criteria: criteria) }
            }
            var best: (Match, Int)?
            for await candidate in group {
                guard let candidate else { continue }
                if best == nil || candidate.1 > best!.1 {
                    best = candidate
                }
                if candidate.1 == 3 {
                    group.cancelAll()
                    break
                }
            }
            return best
        }
    }

    private static func bestMatch(
        in client: MusicAddonClient,
        query: String,
        criteria: Criteria
    ) async -> (Match, Int)? {
        guard let found = try? await client.search(query, limit: 8), !found.isEmpty else { return nil }
        var best: (Match, Int)?
        for track in found {
            guard TextMatch.titlesMatch(track.title, criteria.title) else { continue }
            if let trackArtist = track.artist, !trackArtist.isEmpty, !criteria.artist.isEmpty,
               !TextMatch.artistsMatch(trackArtist, criteria.artist) { continue }
            if let album = criteria.album, !album.isEmpty, let trackAlbum = track.album, !trackAlbum.isEmpty,
               !TextMatch.albumsMatch(trackAlbum, album) { continue }
            if let duration = criteria.duration, let trackDuration = track.durationSeconds, trackDuration > 0,
               abs(trackDuration - duration) > 20 { continue }
            guard let stream = try? await client.resolveStream(type: track.type, id: track.id) else { continue }
            let rank: Int
            switch stream.qualityTier {
            case "Lossless": rank = 3
            case "High": rank = 2
            default: rank = 1
            }
            if best == nil || rank > best!.1 {
                best = (Match(track: track, stream: stream), rank)
            }
        }
        return best
    }
}
