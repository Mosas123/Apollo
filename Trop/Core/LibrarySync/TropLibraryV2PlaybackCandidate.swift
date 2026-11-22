import Foundation

/// A playback item is a candidate to save, not the authoritative Trop ID.
/// The user must explicitly choose Save or Add to Playlist.
struct TropLibraryV2PlaybackCandidate: Sendable {
    let title: String
    let artist: String?
    let durationSeconds: Int
    let provider: String
    let externalID: String

    static func sourceReference(for playbackID: String) -> (
        provider: String, externalID: String
    )? {
        if let catalogue = MusicCatalogID(storageKey: playbackID) {
            return (catalogue.source.rawValue, catalogue.rawValue)
        }
        if MusicPlaybackIdentity.isYouTube(playbackID) {
            return ("youtube", playbackID)
        }
        // Live radio, podcast transient IDs, or unsupported providers must
        // not be mistaken for a canonical recording.
        return nil
    }

    /// Preserve the explicitly tapped track's provider-scoped identity.
    /// A search-row menu must not accidentally save the currently playing
    /// song (or treat an Eclipse add-on ID as a YouTube video ID).
    @MainActor
    static func fromSong(_ song: SongItem) -> TropLibraryV2PlaybackCandidate? {
        guard let source = sourceReference(for: song.videoId) else { return nil }
        return TropLibraryV2PlaybackCandidate(
            title: song.title,
            artist: song.artistNamesDisplay,
            durationSeconds: max(0, song.duration),
            provider: source.provider,
            externalID: source.externalID
        )
    }

    @MainActor
    static func current() -> TropLibraryV2PlaybackCandidate? {
        let player = NowPlaying.shared
        guard let playbackID = player.videoId, !playbackID.isEmpty else {
            return nil
        }
        guard let source = sourceReference(for: playbackID) else { return nil }
        let duration = player.duration.isFinite
            ? max(0, Int(min(player.duration, Double(Int.max / 2))))
            : 0
        return TropLibraryV2PlaybackCandidate(
            title: player.displayTitle,
            artist: player.displayArtist,
            durationSeconds: duration,
            provider: source.provider,
            externalID: source.externalID
        )
    }

    @discardableResult
    func save(liked: Bool = false) async throws -> String {
        try await TropLibraryV2Store.savePlaybackRecording(
            title: title, artist: artist, durationSeconds: durationSeconds,
            provider: provider, externalID: externalID, liked: liked
        )
    }
}


/// Playback starts from a saved Trop UUID, but the queue receives ONLY a
/// known provider-scoped audio ID. An unresolved/ambiguous playlist fails
/// atomically instead of dropping items or silently searching YouTube.
@MainActor
enum TropLibraryV2PlaybackRouter {
    private static var requestGeneration = 0

    static func playSaved(_ recording: TropLibraryV2Store.RecordingSummary) async throws {
        requestGeneration += 1
        let request = requestGeneration
        let playerGeneration = NowPlaying.shared.playbackGeneration
        let aliases = try await TropLibraryV2Store.sourceAliases(forRecordingID: recording.id)
        let key = try TropLibraryV2PlaybackSourcePolicy.playbackKey(for: aliases)
        guard !Task.isCancelled, request == requestGeneration,
              playerGeneration == NowPlaying.shared.playbackGeneration else {
            throw CancellationError()
        }
        let song = makeSong(
            playbackKey: key, title: recording.title,
            artist: recording.artist, duration: recording.durationSeconds
        )
        PlaybackQueue.play(
            [song], log: Log.libraryView, context: "Library V2 saved song"
        )
    }

    /// Retain the exact membership order, including duplicate recordings.
    /// Do not partially play a playlist when any entry lacks a safe source.
    static func playPlaylist(
        _ tracks: [TropLibraryV2Store.PlaylistTrack],
        startingAt selectedIndex: Int
    ) async throws {
        guard tracks.indices.contains(selectedIndex) else {
            throw TropLibraryV2PlaybackSourceError.unavailable
        }
        requestGeneration += 1
        let request = requestGeneration
        let playerGeneration = NowPlaying.shared.playbackGeneration
        var queue: [SongItem] = []
        queue.reserveCapacity(tracks.count)
        for track in tracks {
            try Task.checkCancellation()
            let aliases = try await TropLibraryV2Store.sourceAliases(
                forRecordingID: track.recordingID
            )
            let key = try TropLibraryV2PlaybackSourcePolicy.playbackKey(for: aliases)
            queue.append(makeSong(
                playbackKey: key, title: track.title,
                artist: track.artist, duration: track.durationSeconds
            ))
        }
        guard !Task.isCancelled, request == requestGeneration,
              playerGeneration == NowPlaying.shared.playbackGeneration else {
            throw CancellationError()
        }
        PlaybackQueue.play(
            queue, startIndex: selectedIndex,
            log: Log.libraryView, context: "Library V2 playlist"
        )
    }

    private static func makeSong(
        playbackKey: String,
        title: String,
        artist: String?,
        duration: Int
    ) -> SongItem {
        let performer = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SongItem(
            videoId: playbackKey,
            title: title,
            artists: performer.isEmpty ? [] : [YTArtist(name: performer, id: nil)],
            album: nil,
            albumId: nil,
            duration: max(0, duration),
            thumbnailUrl: nil,
            isExplicit: false,
            playlistId: nil,
            likeStatus: nil,
            contentKind: .music
        )
    }
}
