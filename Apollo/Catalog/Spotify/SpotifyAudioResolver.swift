import Foundation

/// Bridges a Spotify catalogue track to a YouTube audio id. Spotify remains
/// the metadata source; YouTube is only asked for a streamable carrier. The
/// match is cached so repeated taps and queue rebuilds do not re-search.
@MainActor
final class SpotifyAudioResolver {
    static let shared = SpotifyAudioResolver()

    private var cache: [String: SongItem] = [:]

    func resolve(_ song: SongItem) async -> SongItem? {
        if let cached = cache[song.videoId] { return cached }

        let title = TextMatch.queryTitle(song.title)
        let artist = song.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""
        let query = [title, artist].filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty else { return nil }

        let json: [String: Any]
        do {
            json = try await SearchService.shared.search(query: query)
        } catch {
            Log.searchView.error("Spotify audio search failed for \(song.videoId): \(error)")
            return nil
        }

        let candidates = SearchParser.parseSearchResults(from: json)
            .flatMap(\.items)
            .compactMap { item -> SongItem? in
                guard case .song(let candidate) = item,
                      !SpotifyCatalogID.isSpotify(candidate.videoId) else { return nil }
                return candidate
            }

        guard let best = bestCandidate(for: song, in: candidates) else {
            Log.searchView.error("No YouTube audio match for Spotify track \(song.videoId)")
            return nil
        }

        var resolved = best
        resolved.title = song.title
        resolved.artists = song.artists
        resolved.album = song.album
        resolved.albumId = song.albumId
        resolved.duration = song.duration > 0 ? song.duration : best.duration
        resolved.thumbnailUrl = song.thumbnailUrl
        resolved.isExplicit = song.isExplicit
        resolved.viewCount = nil
        resolved.year = song.year
        resolved.recordingPreference = .albumAudio
        resolved.contentKind = .music

        cache[song.videoId] = resolved
        return resolved
    }

    private func bestCandidate(for song: SongItem, in candidates: [SongItem]) -> SongItem? {
        let wantedTitle = TextMatch.normalizeTitle(song.title)
        let wantedArtist = song.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""

        let scored = candidates.compactMap { candidate -> (SongItem, Int)? in
            let title = TextMatch.normalizeTitle(candidate.title)
            let artist = candidate.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""

            var score = 0
            if title == wantedTitle {
                score += 100
            } else if !wantedTitle.isEmpty, title.contains(wantedTitle) || wantedTitle.contains(title) {
                score += 45
            } else {
                return nil
            }

            if !wantedArtist.isEmpty {
                if artist == wantedArtist {
                    score += 40
                } else if artist.contains(wantedArtist) || wantedArtist.contains(artist) {
                    score += 20
                }
            }

            if song.duration > 0, candidate.duration > 0 {
                let delta = abs(candidate.duration - song.duration)
                if delta <= 5 { score += 30 } else if delta <= 15 { score += 10 } else if delta > 45 { return nil }
            }

            if candidate.isVideo == true { score -= 5 }
            return (candidate, score)
        }

        return scored.max { $0.1 < $1.1 }?.0
    }
}
