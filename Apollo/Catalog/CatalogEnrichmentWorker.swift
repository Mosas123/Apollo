import Foundation

/// Background enrichment with a small, serial queue. Search, home and playback
/// enqueue only a bounded prefix, so catalogue use never fans out into dozens
/// of Apple/MusicBrainz requests or blocks the UI.
actor CatalogEnrichmentWorker {
    static let shared = CatalogEnrichmentWorker()

    private var pending: [CatalogTrack] = []
    private var queued = Set<String>()
    private var processing = false
    private let maxPending = 40

    func enqueue(_ tracks: [CatalogTrack]) {
        for track in tracks {
            guard !track.title.isEmpty else { continue }
            let key = "\(track.source.rawValue)|\(track.id)"
            guard queued.insert(key).inserted else { continue }
            pending.append(track)
        }

        while pending.count > maxPending {
            let dropped = pending.removeFirst()
            queued.remove("\(dropped.source.rawValue)|\(dropped.id)")
        }

        startIfNeeded()
    }

    private func startIfNeeded() {
        guard !processing, !pending.isEmpty else { return }
        processing = true
        Task { await processLoop() }
    }

    private func processLoop() async {
        while !pending.isEmpty {
            let track = pending.removeFirst()
            let key = "\(track.source.rawValue)|\(track.id)"
            let enrichment = await CatalogEnricher().enrich(track)
            _ = await CatalogMerger.shared.merge(track, enrichment: enrichment)
            queued.remove(key)
            NotificationCenter.default.post(name: .catalogEnrichmentUpdated, object: nil)
        }
        processing = false
        startIfNeeded()
    }
}

extension CatalogTrack {
    /// Minimal Spotify record built from a UI song, used by the background
    /// enricher without waiting for the detail endpoint.
    static func spotifyStub(from song: SongItem) -> CatalogTrack? {
        guard SpotifyCatalogID.isSpotify(song.videoId),
              let trackID = SpotifyCatalogID.rawID(song.videoId) else {
            return nil
        }

        let artists = song.artists.map { artist -> CatalogArtist in
            let id = artist.id.flatMap { SpotifyCatalogID.isSpotify($0) ? SpotifyCatalogID.rawID($0) : $0 }
            return CatalogArtist(id: id ?? artist.name, name: artist.name, artworkURL: nil)
        }
        let albumID = song.albumId.flatMap { SpotifyCatalogID.rawID($0) }
        let album = song.album.flatMap { title in
            albumID.map {
                CatalogAlbumRef(
                    id: $0,
                    title: title,
                    artworkURL: song.thumbnailUrl.flatMap(URL.init(string:))
                )
            }
        }

        return CatalogTrack(
            id: trackID,
            source: .spotify,
            title: song.title,
            artists: artists,
            album: album,
            durationMS: max(0, song.duration * 1000),
            isrc: nil,
            artworkURL: song.thumbnailUrl.flatMap(URL.init(string:)),
            externalURL: URL(string: "https://open.spotify.com/track/\(trackID)"),
            isExplicit: song.isExplicit == true
        )
    }
}
