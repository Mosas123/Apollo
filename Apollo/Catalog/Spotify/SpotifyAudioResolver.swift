import Foundation

/// Bridges a Spotify catalogue track to a YouTube audio id. Spotify remains
/// the metadata source; YouTube is only asked for a streamable carrier. The
/// match is cached so repeated taps and queue rebuilds do not re-search.
@MainActor
final class SpotifyAudioResolver {
    static let shared = SpotifyAudioResolver()

    private var cache: [String: SongItem] = [:]
    private var tail: Task<Void, Never>?

    func resolve(_ song: SongItem) async -> SongItem? {
        if let stub = CatalogTrack.spotifyStub(from: song) {
            Task { await CatalogEnrichmentWorker.shared.enqueue([stub]) }
        }

        if let cached = cache[song.videoId] { return cached }

        // Downloads and queue prefetch can ask for several tracks at once.
        // SearchService cancels its previous query, so resolutions are
        // serialized instead of racing each other.
        let previous = tail
        let task = Task { @MainActor [weak self] () -> SongItem? in
            await previous?.value
            guard let self else { return nil }
            if let cached = self.cache[song.videoId] { return cached }
            let result = await self.resolveOne(song)
            if let result { self.cache[song.videoId] = result }
            return result
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    private func resolveOne(_ song: SongItem) async -> SongItem? {
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
            if let fallback = await fallbackCandidate(for: song) {
                cache[song.videoId] = fallback
                return fallback
            }
            Log.searchView.error("No audio match for Spotify track \(song.videoId)")
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

        return resolved
    }

    /// When YouTube has no carrier, ask the formal audio providers. ISRC is
    /// used when both sides expose it; otherwise metadata decides.
    private func fallbackCandidate(for song: SongItem) async -> SongItem? {
        var isrc = song.isrc
        if isrc == nil, let spotifyID = song.catalogID.flatMap(SpotifyCatalogID.rawID) {
            isrc = await CatalogIdentityStore.isrc(forSpotifyTrackID: spotifyID)
        }

        let registry = AudioProviderRegistry.forQuality(SettingsStore.shared.activeStreamingMode)
        guard let match = await registry.bestCandidate(for: song, isrc: isrc) else { return nil }

        var resolved = match.song
        resolved.title = song.title
        resolved.artists = song.artists
        resolved.album = song.album
        resolved.albumId = song.albumId
        resolved.duration = song.duration > 0 ? song.duration : match.song.duration
        resolved.thumbnailUrl = song.thumbnailUrl ?? match.song.thumbnailUrl
        resolved.isExplicit = song.isExplicit
        resolved.year = song.year
        resolved.contentKind = .music
        resolved.catalogID = song.catalogID
        resolved.isrc = match.isrc ?? isrc
        resolved.stationReason = song.stationReason
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
