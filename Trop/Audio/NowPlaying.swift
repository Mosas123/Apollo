//
//  NowPlaying.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import AVFoundation
import Foundation
import Observation
import Nuke
import SwiftUI

/// The song currently playing on a radio stream (from ICY metadata), enriched
/// with canonical metadata and artwork when available.
struct LiveSongInfo: Equatable {
    var title: String
    var artist: String
    var album: String?
    var artwork: Data?
}

/// What is currently playing, used to route metadata and label the UI.
enum PlaybackKind: Sendable {
    case music
    case podcast
    case radio
}

@MainActor
@Observable
final class NowPlaying {
    static let shared = NowPlaying()
    /// Synchronous radio streams use a synthetic `radio:<uuid>` video id.
    static let radioPrefix = "radio:"

    var title = ""
    var artist = ""
    /// For internet radio: the song currently playing on the station (ICY title).
    var liveTitle: String?
    /// Enriched live radio song (parsed + album/artwork from a catalogue).
    var liveSongInfo: LiveSongInfo?
    var albumTitle = ""
    var videoId: String?
    var artists: [YTArtist] = []
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Float {
        duration > 0 ? Float(currentTime / duration) : 0
    }
    var thumbnailImage: Image?
    var thumbnailUIImage: UIImage?
    var thumbnailVersion = 0
    var dominantColors: [Color] = [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.05, green: 0.05, blue: 0.08)]

    var accentColor: Color? {
        guard videoId != nil, let primary = dominantColors.first else { return nil }
        return primary
    }

    var queueSongs: [SongItem] = []
    var queueIndex = 0

    var isShuffleOn = false
    var isRepeatOn = false

    var hasVideo: Bool = false
    var isVideoMode: Bool = false
    var isVideoReady: Bool = false
    var musicVideoType: String?

    private var originalQueue: [SongItem]?

    var hasNext: Bool {
        queueIndex + 1 < queueSongs.count
    }

    var hasPrevious: Bool {
        queueIndex > 0
    }

    var isBarPresented: Bool {
        videoId != nil
    }

    /// Whether the current playback is music, a podcast, or internet radio.
    var playbackKind: PlaybackKind {
        if videoId?.hasPrefix(Self.radioPrefix) == true { return .radio }
        if queueSongs.indices.contains(queueIndex) {
            let kind = queueSongs[queueIndex].contentKind
            if kind == .episode || kind == .podcast { return .podcast }
        }
        return .music
    }

    private var timer: Timer?
    private var icyTick = 0
    var sleepTimerEndsAt: Date?
    @ObservationIgnored private var sleepTimerTask: Task<Void, Never>?
    var lastManualSkipTime: Date?
    private var isResolvingNext = false
    private var consecutiveFailures = 0
    private static let maxConsecutiveFailures = 3
    /// Timestamps of the last mid-play failure per videoId, to bound retries.
    private var lastFailureAt: [String: Date] = [:]

    private static let queueKey = "nowPlaying.queue"
    private static let queueIndexKey = "nowPlaying.queueIndex"
    private static let shuffleKey = "nowPlaying.shuffle"
    private static let repeatKey = "nowPlaying.repeat"

    private init() {
        restoreQueueIfNeeded()
    }

    deinit {
        Task { @MainActor [weak self] in self?.stopTimer() }
    }

    // MARK: - Persistent queue

    private func restoreQueueIfNeeded() {
        guard SettingsStore.shared.persistQueue,
              let data = UserDefaults.standard.data(forKey: Self.queueKey),
              let songs = try? JSONDecoder().decode([SongItem].self, from: data),
              !songs.isEmpty else { return }
        queueSongs = songs
        // integer(forKey:) returns 0 even when key missing – distinguish via object(forKey:)
        let storedIndex: Int
        if UserDefaults.standard.object(forKey: Self.queueIndexKey) != nil {
            storedIndex = UserDefaults.standard.integer(forKey: Self.queueIndexKey)
        } else {
            storedIndex = 0
        }
        queueIndex = min(max(storedIndex, 0), songs.count - 1)
        isShuffleOn = UserDefaults.standard.bool(forKey: Self.shuffleKey)
        isRepeatOn = UserDefaults.standard.bool(forKey: Self.repeatKey)
        queueIndex = max(0, queueIndex)
    }

    func persistQueueState() {
        guard SettingsStore.shared.persistQueue else { return }
        if queueSongs.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.queueKey)
            UserDefaults.standard.removeObject(forKey: Self.queueIndexKey)
            UserDefaults.standard.removeObject(forKey: Self.shuffleKey)
            UserDefaults.standard.removeObject(forKey: Self.repeatKey)
            return
        }
        if let data = try? JSONEncoder().encode(queueSongs) {
            UserDefaults.standard.set(data, forKey: Self.queueKey)
        }
        UserDefaults.standard.set(queueIndex, forKey: Self.queueIndexKey)
        UserDefaults.standard.set(isShuffleOn, forKey: Self.shuffleKey)
        UserDefaults.standard.set(isRepeatOn, forKey: Self.repeatKey)
    }

    func setQueue(_ songs: [SongItem], startIndex: Int) {
        queueSongs = songs
        queueIndex = min(max(startIndex, 0), max(songs.count - 1, 0))
        originalQueue = nil
        isShuffleOn = false
        persistQueueState()
    }

    /// Ensures `queueIndex` points at a valid entry
    func repairQueueIndex() {
        if queueSongs.isEmpty {
            queueIndex = 0
            return
        }
        if let videoId, let idx = queueSongs.firstIndex(where: { $0.videoId == videoId }) {
            queueIndex = idx
        } else {
            queueIndex = min(max(queueIndex, 0), queueSongs.count - 1)
        }
    }

    func upcomingSongs(prefixLimit: Int? = nil) -> [SongItem] {
        let next = queueIndex + 1
        guard queueSongs.indices.contains(next) else { return [] }
        let rest = Array(queueSongs[next...])
        guard let prefixLimit else { return rest }
        return Array(rest.prefix(prefixLimit))
    }

    /// Shuffles upcoming songs, keeping the current one; tapping again re-shuffles.
    func shuffleQueue() {
        guard queueSongs.count > 1 else {
            isShuffleOn = true
            return
        }
        if originalQueue == nil {
            originalQueue = queueSongs
        }
        guard queueSongs.indices.contains(queueIndex) else { return }
        let prefix = queueIndex > 0 ? Array(queueSongs[0..<queueIndex]) : []
        let current = queueSongs[queueIndex]
        var rest = queueIndex + 1 < queueSongs.count ? Array(queueSongs[(queueIndex + 1)...]) : []
        rest.shuffle()
        queueSongs = prefix + [current] + rest
        queueIndex = prefix.count
        isShuffleOn = true
        persistQueueState()
    }

    /// Restore the original (unshuffled) queue order.
    func disableShuffle() {
        guard queueSongs.indices.contains(queueIndex) else { return }
        if let orig = originalQueue {
            let currentVideoId = queueSongs[queueIndex].videoId
            queueSongs = orig
            // The shuffled index is meaningless against the original array
            // (radio appends, deletes and reorders change lengths).
            let restored = orig.firstIndex(where: { $0.videoId == currentVideoId }) ?? queueIndex
            queueIndex = min(restored, max(orig.count - 1, 0))
        }
        originalQueue = nil
        isShuffleOn = false
        persistQueueState()
    }

    func moveQueueSongs(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty, queueSongs.indices.contains(source.first ?? -1) else { return }
        queueSongs.move(fromOffsets: source, toOffset: destination)
        repairQueueIndex()
        persistQueueState()
    }

    func repeatCurrent() {
        guard queueSongs.indices.contains(queueIndex) else { return }
        playCurrentSong(logContext: "repeatCurrent") {
            self.isRepeatOn = false
        }
    }

    func playNext(automatic: Bool = false) {
        guard hasNext else { return }
        guard !isResolvingNext else { return }
        if !automatic { lastManualSkipTime = Date() }
        queueIndex += 1
        playCurrentSong(logContext: "playNext")
    }

    func playPrevious() {
        guard hasPrevious else { return }
        guard !isResolvingNext else { return }
        lastManualSkipTime = Date()
        queueIndex -= 1
        playCurrentSong(logContext: "playPrevious")
    }

    /// Starts the song at `queueIndex`: pushes metadata, persists the queue,
    /// and resolves the stream, clearing `isResolvingNext` afterwards.
    /// Shared by repeatCurrent/playNext/playPrevious and QueueView playback.
    func playCurrentSong(
        logContext: String,
        manageResolvingFlag: Bool = true,
        afterResolve: (() -> Void)? = nil
    ) {
        guard queueSongs.indices.contains(queueIndex) else { return }
        if manageResolvingFlag {
            isResolvingNext = true
        }
        let song = queueSongs[queueIndex]
        update(with: song)
        persistQueueState()
        Task {
            var failed = false
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
                consecutiveFailures = 0
            } catch {
                failed = true
                Log.nowPlaying.error("\(logContext) failed for \(song.videoId): \(error)")
                if self.videoId == song.videoId {
                    isPlaying = false
                }
            }
            if manageResolvingFlag {
                isResolvingNext = false
            }
            afterResolve?()
            if failed {
                handlePlaybackFailure(failedVideoId: song.videoId)
            }
        }
    }

    func update(title: String, artist: String?, videoId: String, album: String? = nil, artists: [YTArtist] = [], thumbnailUrl: String? = nil) {
        self.isPlaying = true
        self.title = title
        self.artists = artists
        self.artist = cleanArtistDisplay(artist ?? "")
        self.albumTitle = album ?? ""
        self.currentTime = 0
        self.duration = 0
        self.videoId = videoId
        self.liveTitle = nil
        self.liveSongInfo = nil
        self.hasVideo = false
        self.isVideoMode = false
        self.isVideoReady = false
        startTimer()
        loadThumbnail(videoId: videoId, thumbnailUrl: thumbnailUrl)
        preloadNextTrack()
        if MusicPlaybackIdentity.isYouTube(videoId) {
            CanvasPrefetch.request(videoId: videoId, title: title, artist: self.artist, album: album)
        }
    }

    /// Convenience pushing a `SongItem`'s metadata into the player state.
    func update(with song: SongItem) {
        update(
            title: song.title,
            artist: song.artists.map(\.name).joined(separator: ", "),
            videoId: song.videoId,
            album: song.album,
            artists: song.artists,
            thumbnailUrl: song.thumbnailUrl
        )
    }

    /// Records video availability: the watchable-video verdict comes from
    /// the shared availability check (row type preferred, authoritative
    /// lookup as fallback); this only stores it alongside the type and
    /// pre-warms when there is one to show.
    func updateVideoAvailability(musicVideoType: String? = nil, hasVideo: Bool = false) {
        if let musicVideoType {
            self.musicVideoType = musicVideoType
        }
        self.hasVideo = hasVideo
        if hasVideo {
            PlayerController.shared.preloadVideoURL()
        }
    }

    /// Pre-warms artwork for the previous and upcoming songs so swiping the
    /// mini player bar shows their art instantly.
    func preloadNeighborArtwork() {
        var urls = upcomingSongs(prefixLimit: 3)
            .compactMap(\.thumbnailUrl)
            .compactMap { URL(string: ArtworkURLs.highRes($0) ?? $0) }
        let neighborIds = queueSongs.indices.compactMap { index -> String? in
            guard index == queueIndex - 1 || (index > queueIndex && index <= queueIndex + 3) else { return nil }
            return queueSongs[index].videoId
        }
        urls.append(contentsOf: neighborIds.compactMap { URL(string: Self.artworkURL(for: $0)) })
        guard !urls.isEmpty else { return }
        Task { await ImagePreloader.shared.append(urls) }
    }

    /// Artist string from `artists`, falling back to `artist`.
    var displayArtist: String {
        let fromArray = artistDisplayString(from: artists)
        if !fromArray.isEmpty { return fromArray }
        return artist
    }

    func stopped(videoId: String?, isEof: Bool = true) {
        guard self.videoId == videoId else { return }
        if let skipTime = lastManualSkipTime, Date().timeIntervalSince(skipTime) < 2, isResolvingNext {
            return
        }
        guard isEof else {
            recoverFromPlaybackFailure(videoId: videoId)
            return
        }
        currentTime = duration
        if let finishedId = videoId,
           duration >= 600 || musicVideoType == "MUSIC_VIDEO_TYPE_PODCAST_EPISODE" {
            Task { await EpisodePlaybackStore.shared.markPlayed(videoId: finishedId) }
        }
        if isRepeatOn {
            repeatCurrent()
            return
        }
        if hasNext {
            playNext(automatic: true)
        } else if SettingsStore.shared.autoplaySimilar,
                  MusicPlaybackIdentity.isYouTube(videoId),
                  let endedVideoId = videoId {
            autoplaySimilar(from: endedVideoId)
        } else {
            // End of queue, pause but keep the last song shown in the player.
            isPlaying = false
            stopTimer()
            PlayerController.shared.updateNowPlayingProgress()
            Task { await PlaybackStateService.shared.stopTracking() }
        }
    }

    /// Continues playback with a radio queue built from the last song when the
    /// queue runs out and "Autoplay Similar" is enabled.
    private func autoplaySimilar(from videoId: String) {
        Task {
            do {
                let radio = try await PersonalizationService.shared.fetchRadio(videoId: videoId)
                let songs = radio.songs
                guard !songs.isEmpty else {
                    isPlaying = false
                    return
                }
                self.queueSongs = songs
                self.queueIndex = 0
                self.isShuffleOn = false
                let first = songs[0]
                update(with: first)
                try await PlaybackManager.shared.resolveAndPlay(videoId: first.videoId)
                self.persistQueueState()
            } catch {
                Log.nowPlaying.error("Autoplay similar failed: \(error)")
                isPlaying = false
            }
        }
    }

    /// A stream that died mid-play (not EOF, not a manual skip): drop the
    /// possibly-expired cached URL and re-resolve once. Repeated failures for
    /// the same video are only retried after a cooldown to avoid a loop.
    /// One bad song (resolve failed, expired stream, region block) must not kill
    /// the session: skip past it, but stop after a few consecutive failures so a
    /// systemic outage doesn't hammer YouTube or loop forever.
    /// Called by the player when a stream resolved but mpv couldn't start it.
    func reportPlaybackFailure(videoId: String) {
        guard self.videoId == videoId else { return }
        handlePlaybackFailure(failedVideoId: videoId)
    }

    private func handlePlaybackFailure(failedVideoId: String) {
        consecutiveFailures += 1
        let canSkip = hasNext && consecutiveFailures < Self.maxConsecutiveFailures
        Log.nowPlaying.notice(
            "Playback failure \(consecutiveFailures)/\(Self.maxConsecutiveFailures) for \(failedVideoId); "
                + (canSkip ? "skipping to next" : "stopping")
        )
        if canSkip {
            playNext(automatic: true)
        } else {
            consecutiveFailures = 0
            isPlaying = false
        }
    }

    private func recoverFromPlaybackFailure(videoId: String?) {
        guard let videoId else {
            isPlaying = false
            return
        }
        PlayerController.shared.handleVideoStreamFailure()
        if let last = lastFailureAt[videoId], Date().timeIntervalSince(last) < 30 {
            isPlaying = false
            return
        }
        lastFailureAt[videoId] = Date()
        isPlaying = false
        Log.nowPlaying.notice("Stream failed mid-play, re-resolving \(videoId)")
        Task {
            await PlayerConfigStore.shared.notifyStreamRejection()
            await StreamCache.shared.remove(videoId: videoId)
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: videoId)
                // Success – allow future retries for this video
                _ = await MainActor.run { self.lastFailureAt.removeValue(forKey: videoId) }
            } catch {
                Log.nowPlaying.error("Mid-play recovery failed: \(error)")
                if self.videoId == videoId {
                    isPlaying = false
                }
            }
        }
    }

    static func artworkURL(for videoId: String) -> String {
        ArtworkURLs.fallback(for: videoId)
    }

    private var lastLoadedVideoId: String?

    private func loadThumbnail(videoId: String, thumbnailUrl: String? = nil) {
        guard videoId != lastLoadedVideoId else { return }
        lastLoadedVideoId = videoId
        // Safety net: callers that resolve without song metadata pass nil.
        // The queue usually still knows this track's artwork — use it rather
        // than falling back to the low-res ytimg default.
        var thumb = thumbnailUrl
        if thumb == nil {
            thumb = queueSongs.first { $0.videoId == videoId }?.thumbnailUrl
        }

        Task {
            // For downloaded songs, try to extract embedded artwork from the local file first.
            if !MusicPlaybackIdentity.isAudius(videoId),
               let localURL = await DownloadManager.shared.localURL(for: videoId) {
                loadArtworkFromLocalFile(localURL, videoId: videoId)
                return
            }
            loadThumbnailFromCDN(videoId: videoId, thumbnailUrl: thumb)
            enrichArtwork(videoId: videoId)
        }
    }

    /// Background metadata enrichment: fetch a canonical cover (iTunes first,
    /// then MusicBrainz / Cover Art Archive) and swap it in if the track is
    /// still current. Keeps the player showing clean, consistent album art.
    private func enrichArtwork(videoId: String) {
        // Radio stations already carry their own name and favicon; never match
        // them against music/podcast catalogues.
        guard playbackKind != .radio, !MusicPlaybackIdentity.isAudius(videoId) else { return }
        let title = title
        let artist = artist
        let kind = queueSongs.first { $0.videoId == videoId }?.contentKind
        guard !title.isEmpty, !artist.isEmpty else { return }
        Task {
            let resolved: ResolvedMetadata?
            if kind == .episode || kind == .podcast {
                resolved = await PodcastMetadataResolver.enrich(title: title, author: artist)
            } else {
                resolved = await MetadataResolver.enrich(title: title, artist: artist)
            }
            guard let resolved, let artworkURL = resolved.artworkURL,
                  let image = try? await ArtworkLoader.image(for: artworkURL) else { return }
            guard lastLoadedVideoId == videoId else { return }
            publishArtwork(image)
        }
    }

    private func loadArtworkFromLocalFile(_ fileURL: URL, videoId: String) {
        Task {
            let asset = AVURLAsset(url: fileURL)
            let metadata = try? await asset.load(.metadata)
            var artworkImage: UIImage?
            if let metadata {
                for item in metadata {
                    if let data = try? await item.load(.dataValue),
                       let image = UIImage(data: data) {
                        artworkImage = image
                        break
                    }
                }
            }

            await MainActor.run {
                guard lastLoadedVideoId == videoId else { return }
                if let artworkImage {
                    publishArtwork(artworkImage)
                } else {
                    loadThumbnailFromCDN(videoId: videoId)
                }
            }
        }
    }

    /// Publishes a loaded image as the current artwork (cropped square).
    private func publishArtwork(_ image: UIImage) {
        let cropped = image.centerCroppedSquare()
        thumbnailUIImage = cropped
        thumbnailImage = Image(uiImage: cropped)
        thumbnailVersion &+= 1
        updateDominantColors(from: cropped)
        PlayerController.shared.updateNowPlayingArtwork()
    }

    private func loadThumbnailFromCDN(videoId: String, thumbnailUrl: String? = nil) {
        // Best source first: the track's own artwork upgraded to full
        // resolution, then ytimg step-downs, then the guaranteed hqdefault.
        var candidates: [String] = []
        if MusicPlaybackIdentity.isAudius(videoId), let thumbnailUrl {
            candidates.append(thumbnailUrl)
        } else if let upgraded = ArtworkURLs.highRes(thumbnailUrl) {
            if let maxRes = ArtworkURLs.maxResVariant(upgraded) {
                candidates.append(maxRes)
            }
            if let standard = ArtworkURLs.sdVariant(upgraded) {
                candidates.append(standard)
            }
            candidates.append(upgraded)
        }
        if !MusicPlaybackIdentity.isAudius(videoId) {
            let fallback = Self.artworkURL(for: videoId)
            if !candidates.contains(fallback) {
                candidates.append(fallback)
            }
        }
        let urls = candidates.compactMap(URL.init(string:))
        guard !urls.isEmpty else {
            thumbnailUIImage = nil
            thumbnailImage = Image(systemName: "music.note")
            thumbnailVersion &+= 1
            updateDominantColors(from: nil)
            return
        }

        // Phase 1: instant paint from the best cached candidate. A lesser
        // cached variant must not shadow a better one — Phase 2 upgrades.
        var paintedIndex: Int?
        for (index, url) in urls.enumerated() {
            if let cached = ArtworkLoader.cachedImage(for: url) {
                publishArtwork(cached)
                paintedIndex = index
                break
            }
        }

        // Phase 2: fetch candidates better than the painted one (or all of
        // them when nothing was painted). First success wins and swaps in.
        let fetchCount = paintedIndex ?? urls.count
        if fetchCount == 0 {
            return
        }
        if paintedIndex == nil {
            thumbnailImage = nil
        }
        Task {
            for url in urls.prefix(fetchCount) {
                guard lastLoadedVideoId == videoId else { return }
                do {
                    let platformImage = try await ArtworkLoader.image(for: url)
                    await MainActor.run {
                        guard self.lastLoadedVideoId == videoId else { return }
                        self.publishArtwork(platformImage)
                    }
                    return
                } catch {
                    continue
                }
            }
            if paintedIndex == nil {
                await MainActor.run {
                    guard self.lastLoadedVideoId == videoId else { return }
                    thumbnailImage = Image(systemName: "music.note")
                    thumbnailVersion &+= 1
                    updateDominantColors(from: nil)
                }
            }
        }
    }

    private func preloadNextTrack() {
        guard hasNext else { return }
        let nextId = queueSongs[queueIndex + 1].videoId
        if MusicPlaybackIdentity.isYouTube(nextId) {
            SponsorBlockIntegration.shared.warm(for: nextId)
        }
        loggedTask(Log.nowPlaying, "Pre-resolve failed") {
            _ = try await PlaybackManager.shared.resolve(videoId: nextId)
            Log.nowPlaying.debug("Pre-resolved next track: \(nextId)")
        }
    }

    private func startTimer() {
        stopTimer()
        // Add to `.common` so progress keeps updating while the user scrolls
        // or drags the slider (the default mode pauses the timer).
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timerTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @MainActor
    private func timerTick() {
        currentTime = PlayerController.shared.currentTime
        duration = PlayerController.shared.duration
        PlayerController.shared.updateNowPlayingProgress()
        if MusicPlaybackIdentity.isYouTube(videoId) {
            SponsorBlockIntegration.shared.tick()
        }
        icyTick += 1
        if icyTick % 4 == 0, playbackKind == .radio {
            refreshLiveTitle()
        }
        if let videoId, duration >= 600 || musicVideoType == "MUSIC_VIDEO_TYPE_PODCAST_EPISODE" {
            let vid = videoId
            let pos = currentTime
            let dur = duration
            Task {
                await EpisodePlaybackStore.shared.savePosition(videoId: vid, position: pos, duration: dur)
            }
        }
    }

    /// Reads the stream's ICY title (the live song on a Shoutcast/Icecast
    /// station) and publishes it when it changes.
    private func refreshLiveTitle() {
        guard let icy = PlayerController.shared.icyTitle(), !icy.isEmpty else { return }
        guard liveTitle != icy else { return }
        liveTitle = icy
        resolveLiveSong(icy)
    }

    /// Splits an ICY title ("Artist - Title") and enriches it with a catalogue
    /// lookup, so the player can show the full song and offer to save it.
    private func resolveLiveSong(_ raw: String) {
        let parts = Self.splitICY(raw)
        liveSongInfo = LiveSongInfo(title: parts.title, artist: parts.artist, album: nil, artwork: nil)
        Task {
            guard let resolved = await MetadataResolver.enrich(title: parts.title, artist: parts.artist) else { return }
            var artwork: Data?
            if let url = resolved.artworkURL {
                artwork = try? await URLSession.shared.data(from: url).0
            }
            guard liveTitle == raw else { return }
            liveSongInfo = LiveSongInfo(
                title: resolved.title,
                artist: resolved.artist,
                album: resolved.album,
                artwork: artwork
            )
        }
    }

    /// Splits a raw ICY stream title into artist and title.
    static func splitICY(_ raw: String) -> (artist: String, title: String) {
        for separator in [" - ", " – ", " — "] {
            if let range = raw.range(of: separator) {
                let artist = raw[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let title = raw[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !artist.isEmpty, !title.isEmpty {
                    return (String(artist), String(title))
                }
            }
        }
        return ("", raw.trimmingCharacters(in: .whitespaces))
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Sleep timer

    /// Schedules a pause after `minutes`, replacing any existing sleep timer.
    func scheduleSleepTimer(minutes: Double) {
        cancelSleepTimer()
        let endsAt = Date().addingTimeInterval(minutes * 60)
        sleepTimerEndsAt = endsAt
        sleepTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow))
            guard let self, !Task.isCancelled else { return }
            self.sleepTimerEndsAt = nil
            PlayerController.shared.setPaused(true)
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEndsAt = nil
    }

    @MainActor
    private func updateDominantColors(from uiImage: UIImage?) {
        guard let uiImage = uiImage else {
            self.dominantColors = [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.05, green: 0.05, blue: 0.08)]
            return
        }
        self.dominantColors = uiImage.extractDominantColors()
    }
}

// MARK: - Module-level artist name cleaner

/// Builds a clean, comma-separated artist string from an artist array, dropping
/// names that clean down to empty (junk/blank entries) so no dangling separator
/// is left behind.
func artistDisplayString(from artists: [YTArtist]) -> String {
    artists
        .map { cleanArtistDisplay($0.name) }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
}

func cleanArtistDisplay(_ name: String) -> String {
    var tempName = name

    // Strip " - Topic"
    for suffix in [" - Topic", " - topic", " - TOPIC"] where tempName.lowercased().hasSuffix(suffix.lowercased()) {
        tempName = String(tempName.dropLast(suffix.count))
    }

    // Strip trailing year "(2025)" / "[2025]"
    if let r = try? NSRegularExpression(pattern: "\\s*[\\(\\[]\\d{4}[\\)\\]]\\s*$") {
        tempName = r.stringByReplacingMatches(
            in: tempName,
            range: NSRange(tempName.startIndex..., in: tempName),
            withTemplate: ""
        )
    }

    // Split on commas, ampersands, and bullet separators (•, ·, |) then drop junk segments
    let separatorSet = CharacterSet(charactersIn: ",&•·|")
    let parts = tempName
        .components(separatedBy: separatorSet)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    let cleanParts = parts.filter { !_isJunkArtistSegment($0) }
    if cleanParts.isEmpty {
        return ""
    }
    return cleanParts.joined(separator: ", ")
}

private func _isJunkArtistSegment(_ segment: String) -> Bool {
    let lower = segment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if lower.isEmpty || lower == "•" || lower == "·" { return true }

    let junkLabels: Set<String> = [
        "song", "video", "track", "music", "podcast", "episode",
        "album", "playlist", "released", "year", "plays", "views",
        "downloads", "listeners", "subscribers", "watchers", "likes"
    ]
    if junkLabels.contains(lower) { return true }

    let patterns = [
        // Number optionally followed by K/M/B/T and an optional metric word
        "^[\\d,\\.]+[KMBT]?\\s*(views|downloads|listeners|subscribers|plays|watchers|likes?)?$",
        "^\\d{4}$",              // bare year
        "^[\\d,\\.\\s]+[KMBT]?$" // purely numeric / abbreviated counts
    ]
    for pattern in patterns where lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
        return true
    }
    return false
}
