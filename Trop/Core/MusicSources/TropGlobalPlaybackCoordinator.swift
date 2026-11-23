import Foundation

enum TropGlobalPlaybackError: LocalizedError {
    case unavailable
    case versionsNeedReview

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "No playable audio found in your enabled providers at the current quality."
        case .versionsNeedReview:
            return "Only uncertain versions were found. Open Search to review alternatives."
        }
    }
}

/// Music catalogue identity is never passed to the audio queue as a URL/ID.
/// A tap resolves a real provider-scoped source, without persisting the result
/// or requiring any entry in the user's private Library V2.
@MainActor
enum TropGlobalPlaybackCoordinator {
    private static var intent = 0

    static func play(_ recording: TropGlobalRecording) async throws {
        intent += 1
        let token = intent
        let playerGeneration = NowPlaying.shared.playbackGeneration

        let metadataOnly = TropLibraryV2Store.RecordingSummary(
            id: recording.id, title: recording.title,
            artist: recording.artist,
            durationSeconds: recording.durationSeconds ?? 0,
            isLiked: false
        )
        let matches = await TropLibraryV2AudioDiscovery.inspect(
            for: metadataOnly,
            requiresLossless: SettingsStore.shared.musicQualityMode.prefersLossless
        )
        try Task.checkCancellation()
        guard token == intent,
              playerGeneration == NowPlaying.shared.playbackGeneration else {
            throw CancellationError()
        }
        let candidate = matches.exact.first
            ?? TropGlobalAudioSelectionPolicy.bestCandidate(
                for: recording, among: matches.review
            )
        guard let candidate else {
            throw matches.review.isEmpty
                ? TropGlobalPlaybackError.unavailable
                : TropGlobalPlaybackError.versionsNeedReview
        }

        // Metadata always comes from the independent catalogue; the audio
        // provider only contributes its stream identity and codec transport.
        var song = candidate.asQueueSong()
        song.title = recording.title
        song.artists = [YTArtist(name: recording.artist, id: nil)]
        song.album = recording.album
        song.duration = recording.durationSeconds ?? candidate.durationSeconds

        if let metadata = await MetadataResolver.enrich(
            title: recording.title, artist: recording.artist,
            album: recording.album, duration: song.duration > 0 ? song.duration : nil
        ), let url = TropLibraryV2ArtworkSelectionPolicy.url(
            title: recording.title, artist: recording.artist, metadata: metadata
        ) {
            song.thumbnailUrl = url.absoluteString
        } else {
            // Do not substitute an unrelated provider video thumbnail.
            song.thumbnailUrl = nil
        }
        try Task.checkCancellation()
        guard token == intent,
              playerGeneration == NowPlaying.shared.playbackGeneration else {
            throw CancellationError()
        }
        PlaybackQueue.play(
            song, in: [song], log: Log.explore, context: "Trop catalogue tap"
        )
    }

    /// Explicit user action. Public catalogue queries never auto-fill Library.
    static func save(_ recording: TropGlobalRecording) async throws {
        let saved = try await TropLibraryV2Store.recordings()
        if saved.contains(where: {
            TextMatch.titlesMatch($0.title, recording.title)
                && TextMatch.artistsMatch($0.artist ?? "", recording.artist)
        }) {
            return
        }
        _ = try await TropLibraryV2Store.createItem(
            kind: .recording, title: recording.title,
            artistOrAuthor: recording.artist,
            durationSeconds: max(0, recording.durationSeconds ?? 0)
        )
    }
}
