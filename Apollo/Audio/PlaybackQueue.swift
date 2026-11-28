//
//  PlaybackQueue.swift
//  Apollo
//
// Created by 686udjie on 12/09/2026.
//

import Foundation

/// Shared queue setup + resolve-and-play flows used by every tap-to-play site.
/// Each entry sets the queue on `NowPlaying` and resolves the stream via
/// `PlaybackManager`, logging failures instead of going silent.
@MainActor
enum PlaybackQueue {
    /// Plays `songs[startIndex]` (clamped). Used by detail play-all / play-song.
    static func play(_ songs: [SongItem], startIndex: Int = 0, log: AppLogger, context: String) {
        guard !songs.isEmpty else { return }
        NowPlaying.shared.isSurpriseSession = false
        let index = min(max(startIndex, 0), songs.count - 1)
        NowPlaying.shared.setQueue(songs, startIndex: index)
        log.info(
            "QUEUE_START context=\(context) index=\(index) count=\(songs.count) videoId=\(songs[index].videoId)"
        )
        // The same generation-fenced start path as Next/Previous owns
        // the selected metadata and bounded unavailable-source recovery.
        // Never leave a failed playlist head pointing at the prior song.
        NowPlaying.shared.playCurrentSong(logContext: context)
    }

    /// Shuffled variant of `play(_:startIndex:)`.
    static func playShuffled(_ songs: [SongItem], log: AppLogger, context: String) {
        guard !songs.isEmpty else { return }
        play(songs.shuffled(), log: log, context: context)
    }

    /// Plays `song`, reusing `songs` as the queue when it contains it.
    static func play(_ song: SongItem, in songs: [SongItem], log: AppLogger, context: String) {
        if let index = songs.firstIndex(where: { $0.videoId == song.videoId }) {
            play(songs, startIndex: index, log: log, context: context)
        } else {
            play([song], log: log, context: context)
        }
    }

    /// Starts a radio queue for `song`: plays it first unless already current,
    /// then replaces the queue with the fetched radio. Used by the song and
    /// player "Start Radio" menu actions.
    static func startRadio(for song: SongItem, options: RadioOptions = .default) {
        let wasCurrent = isRadioSeedCurrent(song)
        if !wasCurrent {
            play([song], log: Log.player, context: "Start radio seed")
        }

        // If the user picks another song while the station is being built,
        // its generation changes and the late station must not replace it.
        let generation = NowPlaying.shared.playbackGeneration
        Task {
            let station = await StationService.shared.radio(for: song, options: options)
            guard generation == NowPlaying.shared.playbackGeneration,
                  !station.isEmpty, isRadioSeedCurrent(song) else { return }

            let seed = NowPlaying.shared.queueSongs.first ?? song
            let seedKey = seed.catalogID ?? seed.videoId
            var queue = [seed]
            queue.append(contentsOf: station.filter {
                ($0.catalogID ?? $0.videoId) != seedKey && $0.videoId != seed.videoId
            })

            NowPlaying.shared.queueSongs = preservingArtists(queue, over: NowPlaying.shared.queueSongs)
            NowPlaying.shared.queueIndex = 0
            NowPlaying.shared.queueDidChange()
        }
    }

    /// The seed may have been replaced by its audio carrier in the queue; the
    /// original catalogue id lets us still recognise it.
    private static func isRadioSeedCurrent(_ song: SongItem) -> Bool {
        if NowPlaying.shared.videoId == song.videoId { return true }
        let seedKey = song.catalogID ?? song.videoId
        guard let first = NowPlaying.shared.queueSongs.first else { return false }
        if first.videoId == song.videoId { return true }
        return (first.catalogID ?? first.videoId) == seedKey
    }

    /// Plays a single song and continues with Apollo's own station. YouTube
    /// Music's recommendation endpoint is no longer used here.
    static func playSingleWithRadio(_ song: SongItem, log: AppLogger) {
        startRadio(for: song, options: .default)
    }

    private static func preservingArtists(_ songs: [SongItem], over current: [SongItem]) -> [SongItem] {
        guard !current.isEmpty else { return songs }
        let existingById = Dictionary(current.map { ($0.videoId, $0) }, uniquingKeysWith: { first, _ in first })
        return songs.map { song in
            guard let old = existingById[song.videoId], old.artists.count > song.artists.count else { return song }
            var merged = song
            merged.artists = old.artists
            return merged
        }
    }
}
