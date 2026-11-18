import Foundation

/// Finds the best addon stream for a song from its metadata. Shared by playback
/// upgrades and (next) lossless downloads, so both use identical matching.
enum AddonSourceResolver {
    struct Match: Sendable {
        let track: AddonTrack
        let stream: AddonStream
    }

    static func bestMatch(for song: SongItem) async -> Match? {
        let installations = MusicAddonsStore.shared.enabledStremioInstallations
        guard !installations.isEmpty else { return nil }
        let title = TextMatch.queryTitle(song.title)
        let artist = TextMatch.queryArtist(song.artists.first?.name ?? "")
        let album = song.album
        let duration = song.duration > 0 ? song.duration : nil
        let queries = [([artist, title].filter { !$0.isEmpty }.joined(separator: " ")),
                       title].filter { !$0.isEmpty }

        var best: (Match, Int)?
        for installation in installations.prefix(4) {
            guard let client = try? MusicAddonClient(installation: installation) else { continue }
            for query in queries {
                guard let found = try? await client.search(query, limit: 8), !found.isEmpty else { continue }
                for track in found {
                    guard TextMatch.titlesMatch(track.title, song.title) else { continue }
                    if let trackArtist = track.artist, !trackArtist.isEmpty, !artist.isEmpty,
                       !TextMatch.artistsMatch(trackArtist, artist) { continue }
                    if let album, !album.isEmpty, let trackAlbum = track.album, !trackAlbum.isEmpty,
                       !TextMatch.albumsMatch(trackAlbum, album) { continue }
                    if let duration, let trackDuration = track.durationSeconds, trackDuration > 0,
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
                if best?.1 == 3 { break }
            }
            if best?.1 == 3 { break }
        }
        return best?.0
    }
}
