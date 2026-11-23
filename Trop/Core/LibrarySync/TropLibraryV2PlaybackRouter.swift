import Foundation

/// Playback starts from a saved Trop UUID, but the queue receives ONLY a
/// known provider-scoped audio ID. An unresolved/ambiguous playlist fails
/// atomically instead of dropping items or silently searching YouTube.
@MainActor
enum TropLibraryV2PlaybackRouter {
    private static var requestGeneration = 0

    private static var requiresLossless: Bool {
        SettingsStore.shared.musicQualityMode.prefersLossless
    }

    /// YouTube can play only a saved, known music video ID when enabled by
    /// the user. The V2 matcher never asks YouTube for a music catalogue.
    private static var youtubeAudioEnabled: Bool {
        UserDefaults.standard.bool(forKey: "trop.match.youtubeAudioEnabled")
    }

    private static var prefersHigh: Bool {
        SettingsStore.shared.musicQualityMode == .high
    }

    static func playSaved(_ recording: TropLibraryV2Store.RecordingSummary) async throws {
        requestGeneration += 1
        let request = requestGeneration
        let playerGeneration = NowPlaying.shared.playbackGeneration
        let currentAliases = try await TropLibraryV2Store.sourceAliases(
            forRecordingID: recording.id
        )
        let key: String
        do {
            key = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
                for: currentAliases, requiresLossless: requiresLossless,
                allowYouTubeAudio: youtubeAudioEnabled, preferHigh: prefersHigh
            )
        } catch let error as TropLibraryV2PlaybackSourceError
            where error == .unavailable || error == .incompatibleQuality {
            // Trop Match never opens a provider picker on a normal Play tap.
            // Only exact-version metadata candidates can be auto-linked.
            // Uncertain editions remain available for explicit review.
            let matches = await TropLibraryV2AudioDiscovery.inspect(
                for: recording, requiresLossless: requiresLossless
            )
            guard !Task.isCancelled, request == requestGeneration,
                  playerGeneration == NowPlaying.shared.playbackGeneration else {
                throw CancellationError()
            }
            guard let candidate = matches.exact.first else {
                throw error
            }
            do {
                try await TropLibraryV2Store.linkConfirmedAudioSource(
                    toRecordingID: recording.id,
                    track: candidate,
                    requiresLossless: requiresLossless
                )
            } catch TropLibraryV2AudioLinkError.existingSource {
                // Preserve the existing link and tell the user an explicit
                // source-quality switch is needed in this first iteration.
                throw TropLibraryV2PlaybackSourceError.incompatibleQuality
            } catch TropLibraryV2AudioLinkError.usedByAnotherRecording {
                throw TropLibraryV2PlaybackSourceError.ambiguous
            }
            let aliases = try await TropLibraryV2Store.sourceAliases(
                forRecordingID: recording.id
            )
            key = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
                for: aliases, requiresLossless: requiresLossless,
                allowYouTubeAudio: youtubeAudioEnabled, preferHigh: prefersHigh
            )
        }
        guard !Task.isCancelled, request == requestGeneration,
              playerGeneration == NowPlaying.shared.playbackGeneration else {
            throw CancellationError()
        }
        let artwork = await verifiedArtwork(
            title: recording.title, artist: recording.artist,
            duration: recording.durationSeconds
        )
        guard !Task.isCancelled, request == requestGeneration,
              playerGeneration == NowPlaying.shared.playbackGeneration else {
            throw CancellationError()
        }
        let song = makeSong(
            playbackKey: key, title: recording.title,
            artist: recording.artist, duration: recording.durationSeconds,
            artworkURL: artwork
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
            let key = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
            for: aliases, requiresLossless: requiresLossless,
                allowYouTubeAudio: youtubeAudioEnabled, preferHigh: prefersHigh
        )
            queue.append(makeSong(
                playbackKey: key, title: track.title,
                artist: track.artist, duration: track.durationSeconds
            ))
        }
        guard !Task.isCancelled, request == requestGeneration,
              playerGeneration == NowPlaying.shared.playbackGeneration else {
            throw CancellationError()
        }
        // The player artwork for the selected V2 recording must not be
        // permanently nil just because its audio ID comes from an addon.
        let selected = tracks[selectedIndex]
        let artwork = await verifiedArtwork(
            title: selected.title, artist: selected.artist,
            duration: selected.durationSeconds
        )
        guard !Task.isCancelled, request == requestGeneration,
              playerGeneration == NowPlaying.shared.playbackGeneration else {
            throw CancellationError()
        }
        if let artwork {
            let aliases = try await TropLibraryV2Store.sourceAliases(
                forRecordingID: selected.recordingID
            )
            let key = try TropLibraryV2PlaybackSourcePolicy.playbackKey(
                for: aliases, requiresLossless: requiresLossless,
                allowYouTubeAudio: youtubeAudioEnabled, preferHigh: prefersHigh
            )
            queue[selectedIndex] = makeSong(
                playbackKey: key, title: selected.title, artist: selected.artist,
                duration: selected.durationSeconds, artworkURL: artwork
            )
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

    private static func verifiedArtwork(
        title: String, artist: String?, duration: Int
    ) async -> String? {
        guard let artist, !artist.isEmpty else { return nil }
        guard let metadata = await MetadataResolver.enrich(
            title: title, artist: artist,
            duration: duration > 0 ? duration : nil
        ), let url = TropLibraryV2ArtworkSelectionPolicy.url(
            title: title, artist: artist, metadata: metadata
        ) else { return nil }
        return url.absoluteString
    }

    private static func makeSong(
        playbackKey: String,
        title: String,
        artist: String?,
        duration: Int,
        artworkURL: String? = nil
    ) -> SongItem {
        let performer = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SongItem(
            videoId: playbackKey,
            title: title,
            artists: performer.isEmpty ? [] : [YTArtist(name: performer, id: nil)],
            album: nil,
            albumId: nil,
            duration: max(0, duration),
            thumbnailUrl: artworkURL,
            isExplicit: false,
            playlistId: nil,
            likeStatus: nil,
            contentKind: .music
        )
    }
}
