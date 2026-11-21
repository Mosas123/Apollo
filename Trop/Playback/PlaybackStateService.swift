//
// PlaybackStateService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

actor PlaybackStateService {
    nonisolated static let shared = PlaybackStateService()
    private let db = DatabaseService.shared
    private let innerTube = InnerTubeClient.tropShared

    private let historyDurationThreshold: TimeInterval = 30
    /// Live radio uses synthetic "radio:<uuid>" ids; they are streams, not
    /// songs, so they must never land in play history or "Keep Listening".
    private static let radioPrefix = "radio:"
    private var currentVideoId: String?
    private var listeningClock = ListeningTimeAccumulator()
    private var trackingEpoch: UInt64 = 0
    private var isTracking = false
    private var hasRecordedPlayback = false
    private var periodicCheckTask: Task<Void, Never>?
    private var bankedPlayTimeMs: Int64 = 0

    private init() {}

    /// The initial position belongs to the selected source, not the previous
    /// decoder. Listening time is measured by actual media-clock movement.
    func startTracking(videoId: String, initialPosition: TimeInterval = 0) {
        guard !videoId.hasPrefix(Self.radioPrefix) else {
            reset()
            Log.playbackState.debug("Skipping tracking for radio stream \(videoId)")
            return
        }
        trackingEpoch &+= 1
        let epoch = trackingEpoch
        currentVideoId = videoId
        listeningClock = ListeningTimeAccumulator()
        listeningClock.observe(
            position: max(0, initialPosition),
            uptime: ProcessInfo.processInfo.systemUptime
        )
        isTracking = true
        hasRecordedPlayback = false
        bankedPlayTimeMs = 0
        Log.playbackState.debug("Started tracking videoId=\(videoId)")

        periodicCheckTask?.cancel()
        periodicCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard let self, !Task.isCancelled else { return }
                await self.sampleAndBank(videoId: videoId, epoch: epoch)
            }
        }
    }

    /// Read the active backend's media clock, not the UI's optimistic Play flag.
    /// Pauses and iOS interruptions leave the clock stationary; user seeks
    /// are filtered by ListeningTimeAccumulator.
    private func samplePosition(videoId: String, epoch: UInt64) async {
        let sample = await MainActor.run { () -> (TimeInterval?, TimeInterval) in
            let uptime = ProcessInfo.processInfo.systemUptime
            guard NowPlaying.shared.videoId == videoId,
                  NowPlaying.shared.playbackKind != .radio else {
                return (nil, uptime)
            }
            return (PlayerController.shared.currentTime, uptime)
        }
        guard isTracking, currentVideoId == videoId, trackingEpoch == epoch else { return }
        if let position = sample.0 {
            listeningClock.observe(position: position, uptime: sample.1)
        }
    }

    private func sampleAndBank(videoId: String, epoch: UInt64) async {
        await samplePosition(videoId: videoId, epoch: epoch)
        guard isTracking, currentVideoId == videoId, trackingEpoch == epoch else { return }
        let playedMs = listeningClock.listenedMilliseconds
        // Keep banking small chunks for Top 100 without counting idle time.
        await bankPlayTime(
            videoId: videoId, elapsedMs: playedMs, minimumMs: 5_000, epoch: epoch
        )
        guard isTracking, currentVideoId == videoId, trackingEpoch == epoch else { return }
        if playedMs >= Int64(historyDurationThreshold * 1_000), !hasRecordedPlayback {
            await firePlayback(videoId: videoId, playTimeMs: playedMs, epoch: epoch)
        }
    }

    func stopTracking() async {
        periodicCheckTask?.cancel()
        periodicCheckTask = nil

        guard isTracking, let videoId = currentVideoId else {
            Log.playbackState.debug("stopTracking called but no active tracking")
            reset()
            return
        }
        let epoch = trackingEpoch
        await samplePosition(videoId: videoId, epoch: epoch)
        guard trackingEpoch == epoch, currentVideoId == videoId else { return }
        let playedMs = listeningClock.listenedMilliseconds
        isTracking = false
        Log.playbackState.debug(
            "Stopped tracking videoId=\(videoId) listened=\(String(format: "%.1f", Double(playedMs) / 1_000))s"
        )

        // Bank the remainder first (down to 1s) so short plays count.
        await bankPlayTime(
            videoId: videoId, elapsedMs: playedMs, minimumMs: 1_000, epoch: epoch
        )
        if trackingEpoch == epoch, currentVideoId == videoId,
           playedMs >= Int64(historyDurationThreshold * 1_000), !hasRecordedPlayback {
            await firePlayback(videoId: videoId, playTimeMs: playedMs, epoch: epoch)
        } else if playedMs < Int64(historyDurationThreshold * 1_000) {
            Log.playbackState.debug(
                "Listened \(String(format: "%.1f", Double(playedMs) / 1_000))s below threshold \(self.historyDurationThreshold)s — skipping history recording"
            )
        }
        if trackingEpoch == epoch { reset() }
    }

    private func firePlayback(videoId: String, playTimeMs: Int64, epoch: UInt64) async {
        guard trackingEpoch == epoch, currentVideoId == videoId,
              !hasRecordedPlayback else { return }
        hasRecordedPlayback = true
        await recordPlayback(videoId: videoId, playTimeMs: playTimeMs, epoch: epoch)
    }

    @discardableResult
    private func bankPlayTime(
        videoId: String, elapsedMs: Int64, minimumMs: Int64, epoch: UInt64
    ) async -> Int64 {
        guard trackingEpoch == epoch, currentVideoId == videoId,
              !videoId.hasPrefix(Self.radioPrefix) else { return 0 }
        guard SettingsStore.shared.trackPlayHistory else { return 0 }
        let prior = bankedPlayTimeMs
        let delta = elapsedMs - prior
        guard delta >= minimumMs, delta > 0, !videoId.isEmpty else { return 0 }
        // Reserve before suspension so a competing periodic tick/Stop cannot
        // bank the same seconds twice while a database operation is in flight.
        bankedPlayTimeMs = elapsedMs
        do {
            await ensureSongEntity(videoId: videoId)
            try await db.incrementTotalPlayTime(songId: videoId, playTimeMs: delta)
            return delta
        } catch {
            if trackingEpoch == epoch, bankedPlayTimeMs == elapsedMs {
                bankedPlayTimeMs = prior
            }
            Log.playbackState.error("Failed to bank play time: \(error)")
            return 0
        }
    }

    /// Inserts the song row when missing (title/artwork from the queue),
    /// so banking and history never hit a missing row. No-op when present.
    private func ensureSongEntity(videoId: String) async {
        let queueSong: SongItem? = await MainActor.run {
            NowPlaying.shared.queueSongs.first(where: { $0.videoId == videoId })
        }
        do {
            try await db.write { db in
                guard try SongEntity.fetchOne(db, key: videoId) == nil else { return }
                let entity = SongEntity(
                    id: videoId,
                    title: queueSong?.title ?? videoId,
                    artistName: queueSong.flatMap { $0.artists.first?.name ?? $0.artistNamesDisplay },
                    albumName: queueSong?.album,
                    duration: queueSong?.duration ?? 0,
                    thumbnailUrl: queueSong?.thumbnailUrl ?? ArtworkURLs.fallback(for: videoId),
                    liked: false,
                    totalPlayTime: 0,
                    inLibrary: nil,
                    libraryAddToken: "",
                    libraryRemoveToken: "",
                    isEpisode: false,
                    isUploaded: false,
                    isVideo: false,
                    createDate: Date(),
                    modifyDate: Date()
                )
                try entity.insert(db, onConflict: .ignore)
                Log.playbackState.debug("Ensured SongEntity for \(videoId)")
            }
        } catch {
            Log.playbackState.error("Failed to ensure song entity: \(error)")
        }
    }

    private func recordPlayback(videoId: String, playTimeMs: Int64, epoch: UInt64) async {
        guard !videoId.hasPrefix(Self.radioPrefix) else { return }
        guard SettingsStore.shared.trackPlayHistory else {
            Log.playbackState.debug("Play history tracking disabled — skipping recording")
            return
        }
        Log.playbackState.debug("Recording playback videoId=\(videoId) playTimeMs=\(playTimeMs)")
        await ensureSongEntity(videoId: videoId)
        do {
            try await db.write { db in
                var event = Event(id: nil, songId: videoId, timestamp: Date(), playTime: playTimeMs)
                event = try event.inserted(db, onConflict: .ignore)
                Log.playbackState.debug("Local event recorded id=\(event.id ?? 0)")
            }

            let now = Date()
            let calendar = Calendar.current
            try await db.incrementPlayCount(songId: videoId, year: calendar.component(.year, from: now), month: calendar.component(.month, from: now))
            Log.playbackState.debug("Play count incremented")

            let banked = await bankPlayTime(
                videoId: videoId, elapsedMs: playTimeMs, minimumMs: 0, epoch: epoch
            )
            if banked > 0 {
                Log.playbackState.debug("Total play time incremented (+\(banked)ms)")
            }

            let trackingUrl = await getCachedTrackingUrl(videoId: videoId)
            if let trackingUrl {
                Log.playbackState.debug("Sending playback to YTM for tracking")
                Task {
                    do {
                        try await InnerTubeClient.tropShared.registerPlayback(trackingUrl: trackingUrl)
                    } catch {
                        Log.playbackState.error("YTM playback registration failed: \(error)")
                    }
                }
            } else {
                Log.playbackState.debug("No cached tracking URL for videoId=\(videoId) — skipping YTM registration")
            }
        } catch {
            Log.playbackState.error("Failed to record playback: \(error)")
        }
    }

    private func getCachedTrackingUrl(videoId: String) async -> String? {
        if let format = try? await db.fetchOne(FormatEntity.self, key: videoId),
           let url = format.playbackUrl {
            return url
        }
        return nil
    }

    private func reset() {
        periodicCheckTask?.cancel()
        periodicCheckTask = nil
        trackingEpoch &+= 1
        currentVideoId = nil
        listeningClock = ListeningTimeAccumulator()
        isTracking = false
        hasRecordedPlayback = false
        bankedPlayTimeMs = 0
    }
}
