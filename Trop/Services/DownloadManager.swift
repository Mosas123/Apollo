//
//  DownloadManager.swift
//  Trop
//
//  Created by 686udjie on 19/07/2026.
//

import AVFoundation
import Combine
import Foundation
import GRDB
import Network
import Nuke
import QuartzCore
import SwiftUI
import UIKit
@preconcurrency import ffmpegkit

/// Per-download progress cell. Isolating the high-frequency 0–99% updates in
/// a per-id object means only that row re-renders, not every row observing
/// the manager.
@MainActor
final class DownloadProgressBox: ObservableObject {
    @Published var fraction: Double = 0
}

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloads: [String: DownloadState] = [:]
    @Published private(set) var tracks: [DownloadedTrackEntity] = []
    @Published private(set) var persistedDownloadCount = 0
    @Published private(set) var isLoaded = false

    enum DownloadState: Equatable {
        case notStarted
        case downloading(Double)
        case completed
        case failed(String)
    }

    nonisolated private static let minimumAudioBytes = 8_192

    private let fileManager = FileManager.default
    private let pathMonitor = NWPathMonitor()
    private var currentPath: NWPath?
    private var isReloading = false
    private var cancelledDownloadIds: Set<String> = []
    private var lastReportedProgress: [String: Double] = [:]
    private var lastProgressTime: [String: CFTimeInterval] = [:]
    private var progressBoxes: [String: DownloadProgressBox] = [:]
    private var activeFFmpegSessions: [String: FFmpegSession] = [:]

    private var tracksById: [String: DownloadedTrackEntity] = [:]

    private var downloadsDir: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Downloads", isDirectory: true)
    }

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.currentPath = path
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.trop.network"))

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reload()
            }
        }

        Task { await reload() }
    }

    private var isOnWiFi: Bool {
        // Until the first path update arrives, don't block downloads.
        guard let currentPath else { return true }
        return currentPath.usesInterfaceType(.wifi) == true
            || currentPath.usesInterfaceType(.wiredEthernet) == true
    }

    // MARK: - Paths

    func fileURL(for song: SongItem, quality: DownloadQuality? = nil) async -> URL {
        await displayDestinationURL(
            title: song.title,
            artist: song.artists.map(\.name).joined(separator: ", "),
            videoId: song.videoId,
            quality: quality
        )
    }

    func displayDestinationURL(title: String, artist: String, videoId: String, quality: DownloadQuality? = nil) async -> URL {
        ensureDirectories()
        let rawStem = title.isEmpty ? videoId : (artist.isEmpty ? title : "\(artist) - \(title)")
        let stem = Self.sanitizeFileName(rawStem)
        let ext = (quality ?? SettingsStore.shared.downloadQuality) == .lossless ? "flac" : "m4a"
        return downloadsDir.appendingPathComponent("\(stem) [\(videoId)].\(ext)")
    }

    /// Strips characters illegal on filesystems, trims whitespace/dots and
    /// caps length for APFS's 255-byte limit.
    nonisolated static func sanitizeFileName(_ name: String) -> String {
        var stem = name.replacingOccurrences(of: "/", with: "-")
        let illegal = CharacterSet(charactersIn: ":\\?%*|\"<>").union(.controlCharacters)
        stem = stem.components(separatedBy: illegal).joined(separator: "-")
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        while stem.utf8.count > 150 { stem = String(stem.dropLast()) }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return stem.isEmpty ? "Untitled" : stem
    }

    /// AAC transcode bitrate for the download quality preference.
    nonisolated static func transcodeBitrate(for quality: DownloadQuality) -> Int? {
        switch quality {
        case .lossless: return nil
        case .auto, .high: return 192_000
        case .standard: return 96_000
        }
    }

    @discardableResult
    func ensureDirectories() -> Bool {
        try? fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        return true
    }

    private func resolvedURL(for track: DownloadedTrackEntity) -> URL? {
        let stored = track.localPath
        let url: URL
        if stored.hasPrefix("/") {
            url = URL(fileURLWithPath: stored)
        } else {
            url = downloadsDir.appendingPathComponent(stored)
        }
        if fileManager.fileExists(atPath: url.path) { return url }

        let fileName = (stored as NSString).lastPathComponent
        if !fileName.isEmpty {
            let byName = downloadsDir.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: byName.path) { return byName }
        }

        return nil
    }

    private func storedPath(for url: URL) -> String {
        url.lastPathComponent
    }

    // MARK: - Reload / reconciliation

    /// Rebuilds the library from the database and the Downloads directory.
    /// Orphaned files are adopted, rows whose files vanished are dropped and
    /// stale absolute paths are rewritten relative to the current container.
    func reload() async {
        guard !isReloading else { return }
        isReloading = true
        defer { isReloading = false }

        ensureDirectories()
        let scanned = await Self.scanDownloads(downloadsDir)

        var rebuilt: [String: DownloadedTrackEntity] = [:]
        let databaseTracks = await fetchAllFromDatabase()

        for track in databaseTracks {
            guard let url = resolvedURL(for: track) ?? scanned[track.id] else {
                _ = try? await DatabaseService.shared.delete(track)
                continue
            }
            var fixed = track
            fixed.localPath = storedPath(for: url)
            if fixed.localPath != track.localPath {
                try? await DatabaseService.shared.save(fixed)
            }
            rebuilt[fixed.id] = fixed
        }

        for (videoId, url) in scanned where rebuilt[videoId] == nil {
            let metadata = await songMetadata(for: videoId)
            let entity = DownloadedTrackEntity(
                id: videoId,
                title: metadata?.title ?? Self.displayTitle(from: url),
                artist: metadata?.artistName ?? "",
                duration: metadata?.duration ?? 0,
                thumbnailUrl: metadata?.thumbnailUrl,
                localPath: storedPath(for: url),
                downloadedAt: (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date()
            )
            _ = try? await DatabaseService.shared.insertOrReplace(entity)
            rebuilt[videoId] = entity
            Log.downloadManager.notice("Recovered orphaned download \(videoId) from \(url.lastPathComponent)")
        }

        apply(rebuilt)
        isLoaded = true
    }

    func reconcileDownloadedFiles() async {
        await reload()
    }

    private func apply(_ newTracks: [String: DownloadedTrackEntity]) {
        tracksById = newTracks
        let sorted = newTracks.values.sorted { $0.downloadedAt > $1.downloadedAt }
        if tracks != sorted { tracks = sorted }
        if persistedDownloadCount != newTracks.count { persistedDownloadCount = newTracks.count }
    }

    /// Directory scan is disk-heavy; run it off the main actor.
    nonisolated private static func scanDownloads(_ dir: URL) async -> [String: URL] {
        await Task.detached(priority: .utility) { scanDownloadsSync(dir) }.value
    }

    nonisolated private static func scanDownloadsSync(_ dir: URL) -> [String: URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var found: [String: URL] = [:]
        var dates: [String: Date] = [:]

        for url in urls where ["m4a", "flac"].contains(url.pathExtension.lowercased()) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard (values?.fileSize ?? 0) >= minimumAudioBytes else { continue }
            guard let videoId = Self.videoId(from: url.lastPathComponent) else { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            if let existingDate = dates[videoId], existingDate >= modified { continue }
            found[videoId] = url
            dates[videoId] = modified
        }
        return found
    }

    /// Extracts the video id from `Artist - Title [<id>].m4a`.
    nonisolated static func videoId(from fileName: String) -> String? {
        let base = (fileName as NSString).deletingPathExtension
        guard let range = base.range(of: #"\[([A-Za-z0-9_-]{6,})\]$"#, options: .regularExpression) else {
            return nil
        }
        let bracketed = base[range]
        return bracketed.dropFirst().dropLast().description
    }

    nonisolated private static func displayTitle(from url: URL) -> String {
        var base = (url.lastPathComponent as NSString).deletingPathExtension
        if let range = base.range(of: #"\s*\[[A-Za-z0-9_-]{6,}\]$"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        return base.isEmpty ? url.lastPathComponent : base
    }

    private func songMetadata(for videoId: String) async -> SongEntity? {
        try? await DatabaseService.shared.fetchOne(SongEntity.self, key: videoId)
    }
}

// MARK: - Download

extension DownloadManager {

    /// Downloads a whole list with bounded concurrency (default 3) instead of
    /// spawning one unbounded task per track.
    func downloadAll(_ songs: [SongItem], maxConcurrent: Int = 3) async {
        guard !songs.isEmpty else { return }
        let limit = max(1, maxConcurrent)
        let manager = DownloadManager.shared
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            while next < songs.count {
                let batch = min(limit, songs.count - next)
                for _ in 0..<batch {
                    let song = songs[next]
                    next += 1
                    group.addTask {
                        await manager.download(song: song)
                    }
                }
                await group.next()
            }
        }
    }

    func download(song: SongItem) async {
        let videoId = song.videoId
        let quality = SettingsStore.shared.downloadQuality
        let previousURL = await localURL(for: videoId)
        if case .downloading = downloads[videoId] {
            Log.downloadManager.debug("Download already in progress for \(videoId)")
            return
        }

        if let existing = previousURL,
           quality != .lossless || existing.pathExtension.lowercased() == "flac",
           let size = try? existing.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size >= Self.minimumAudioBytes {
            downloads[videoId] = .completed
            if tracksById[videoId] == nil {
                await adoptExistingFile(at: existing, song: song)
            }
            return
        }

        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "trop-download-\(videoId)") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        defer {
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }

        cancelledDownloadIds.remove(videoId)
        clearProgress(for: videoId)
        let artist = song.artists.map(\.name).joined(separator: ", ")
        let downloadStart = CFAbsoluteTimeGetCurrent()
        Log.downloadManager.debug("Starting download: \(artist) - \(song.title) (\(videoId))")

        if SettingsStore.shared.wifiOnlyDownloads, !isOnWiFi {
            downloads[videoId] = .failed("Wi-Fi Only is enabled and you are not on Wi-Fi.")
            return
        }

        setProgress(0.02, for: videoId)

        let fileURL = await fileURL(for: song, quality: quality)
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }

            async let artworkData = prefetchArtwork(for: song)

            setProgress(0.05, for: videoId)
            let resolveStart = CFAbsoluteTimeGetCurrent()
            let result: PlaybackResult
            if quality == .lossless {
                result = try await PlaybackManager.shared.resolveLosslessDownload(song: song)
            } else {
                result = try await PlaybackManager.shared.resolve(videoId: videoId, forDownload: true, downloadQuality: quality)
            }
            let isFLAC = quality == .lossless
            guard !isFLAC || result.mimeType.lowercased() == "audio/flac" else {
                throw DownloadError.losslessUnavailable
            }
            let resolveElapsed = CFAbsoluteTimeGetCurrent() - resolveStart
            let streamURL = result.streamUrl
            let isAACStream = result.mimeType.lowercased().contains("mp4a")
                || result.mimeType.lowercased().contains("aac")
            Log.downloadManager.debug("RESOLVE \(String(format: "%.1f", resolveElapsed))s codec=\(result.mimeType) isAAC=\(isAACStream)")

            guard let url = URL(string: streamURL) else {
                throw DownloadError.invalidStreamURL
            }

            let tempDownload = fileManager.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(isFLAC ? "flac" : (isAACStream ? "m4a" : "webm"))")
            defer { try? fileManager.removeItem(at: tempDownload) }
            let dlStart = CFAbsoluteTimeGetCurrent()
            try await downloadToFile(
                from: url,
                to: tempDownload,
                videoId: videoId
            )
            let dlElapsed = CFAbsoluteTimeGetCurrent() - dlStart
            let dlSize = (try? tempDownload.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            Log.downloadManager.debug("DOWNLOAD \(String(format: "%.1f", dlElapsed))s \(dlSize / 1024)KB")

            let artwork = await artworkData

            ensureDirectories()
            setProgress(0.88, for: videoId)
            let ffmpegStart = CFAbsoluteTimeGetCurrent()
            if isFLAC {
                try await validateDownloadedFile(at: tempDownload, expectedDuration: song.duration)
                // FLAC container + copied audio preserves original samples.
                try await attachMetadata(
                    to: tempDownload, title: song.title, artist: artist,
                    artworkData: artwork, videoId: videoId
                )
                try await validateDownloadedFile(at: tempDownload, expectedDuration: song.duration)
                try fileManager.moveItem(at: tempDownload, to: fileURL)
            } else if isAACStream {
                // AVFoundation can open AAC/MP4; validate before remux.
                let validateStart = CFAbsoluteTimeGetCurrent()
                try await validateDownloadedFile(at: tempDownload)
                Log.downloadManager.debug("VALIDATE \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - validateStart))s")

                Log.downloadManager.debug("FFMPEG remux (AAC passthrough)...")
                try await attachMetadata(
                    to: tempDownload,
                    title: song.title,
                    artist: artist,
                    artworkData: artwork,
                    videoId: videoId
                )
                try fileManager.moveItem(at: tempDownload, to: fileURL)
            } else {
                // WebM/Opus is not readable by AVFoundation — transcode first,
                // then validate the generated .m4a.
                Log.downloadManager.debug("FFMPEG transcode (Opus -> AAC)...")
                try await processAudio(
                    TranscodeRequest(
                        inputURL: tempDownload,
                        outputURL: fileURL,
                        title: song.title,
                        artist: artist,
                        artworkData: artwork
                    ),
                    videoId: videoId,
                    quality: quality
                )
                let validateStart = CFAbsoluteTimeGetCurrent()
                do {
                    try await validateDownloadedFile(at: fileURL)
                } catch {
                    try? fileManager.removeItem(at: fileURL)
                    throw error
                }
                Log.downloadManager.debug("VALIDATE \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - validateStart))s")
            }
            Log.downloadManager.debug("FFMPEG \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - ffmpegStart))s")

            if cancelledDownloadIds.contains(videoId) {
                cancelledDownloadIds.remove(videoId)
                clearProgress(for: videoId)
                try? fileManager.removeItem(at: fileURL)
                downloads[videoId] = .notStarted
                return
            }

            let entity = DownloadedTrackEntity(
                id: videoId,
                title: song.title,
                artist: artist,
                duration: song.duration,
                thumbnailUrl: song.thumbnailUrl,
                localPath: storedPath(for: fileURL),
                downloadedAt: Date()
            )
            let registered = await register(entity)
            if registered, let previousURL, previousURL != fileURL,
               tracksById[videoId]?.localPath == storedPath(for: fileURL) {
                try? fileManager.removeItem(at: previousURL)
            }

            downloads[videoId] = .completed
            clearProgress(for: videoId)
            let totalElapsed = CFAbsoluteTimeGetCurrent() - downloadStart
            Log.downloadManager.debug("DONE \(String(format: "%.1f", totalElapsed))s total: \(artist) - \(song.title)")
        } catch is CancellationError {
            cancelledDownloadIds.remove(videoId)
            clearProgress(for: videoId)
            try? fileManager.removeItem(at: fileURL)
            downloads[videoId] = .notStarted
        } catch {
            if cancelledDownloadIds.contains(videoId) || (error as? URLError)?.code == .cancelled {
                cancelledDownloadIds.remove(videoId)
                clearProgress(for: videoId)
                try? fileManager.removeItem(at: fileURL)
                downloads[videoId] = .notStarted
                return
            }
            if downloads[videoId] != .completed {
                try? fileManager.removeItem(at: fileURL)
            }
            downloads[videoId] = .failed(userFacingDownloadError(error))
            clearProgress(for: videoId)
            Log.downloadManager.error("Failed download \(videoId): \(error.localizedDescription)")
        }
    }

    private func adoptExistingFile(at url: URL, song: SongItem) async {
        let entity = DownloadedTrackEntity(
            id: song.videoId,
            title: song.title,
            artist: song.artists.map(\.name).joined(separator: ", "),
            duration: song.duration,
            thumbnailUrl: song.thumbnailUrl,
            localPath: storedPath(for: url),
            downloadedAt: (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? Date()
        )
        await register(entity)
    }

    @discardableResult
    private func register(_ entity: DownloadedTrackEntity) async -> Bool {
        tracksById[entity.id] = entity
        apply(tracksById)
        do {
            try await DatabaseService.shared.insertOrReplace(entity)
            return true
        } catch {
            Log.downloadManager.error("Failed to persist download \(entity.id): \(error)")
            return false
        }
    }

    // MARK: - Validation & Errors

    private func validateDownloadedFile(at url: URL, expectedDuration: Int? = nil) async throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        // Real audio streams are well above this; error/HTML bodies are not.
        guard size >= Self.minimumAudioBytes else {
            Log.downloadManager.error("Downloaded file too small (\(size) bytes) — likely a dead stream URL")
            throw DownloadError.invalidStreamURL
        }

        if url.pathExtension.lowercased() == "flac" {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard try handle.read(upToCount: 4) == Data("fLaC".utf8) else {
                throw DownloadError.losslessUnavailable
            }
        }
        let asset = AVURLAsset(url: url)
        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            Log.downloadManager.error("Cannot open downloaded file as audio: \(error.localizedDescription)")
            throw DownloadError.invalidStreamURL
        }
        guard !audioTracks.isEmpty else {
            Log.downloadManager.error("Downloaded file has no audio track — rejecting as invalid stream")
            throw DownloadError.invalidStreamURL
        }
        if let expectedDuration, expectedDuration > 0 {
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0,
                  abs(duration - Double(expectedDuration)) <= 15 else {
                throw DownloadError.invalidStreamURL
            }
        }
    }

    private func userFacingDownloadError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection."
            case .timedOut:
                return "The download timed out."
            default:
                break
            }
        }
        if let downloadError = error as? DownloadError {
            return downloadError.errorDescription ?? "Download failed. Try again."
        }
        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain {
            return "Could not process this track for offline playback. Try again."
        }
        return "Download failed. Try again."
    }

    // MARK: - State

    static func shouldRefreshPersistedLibrary(
        old: [String: DownloadState],
        new: [String: DownloadState]
    ) -> Bool {
        for (videoId, newState) in new {
            let oldState = old[videoId] ?? .notStarted
            if oldState == newState { continue }
            switch (oldState, newState) {
            case (.downloading, .completed), (.downloading, .failed),
                 (.completed, .notStarted), (.failed, .notStarted),
                 (.notStarted, .completed):
                return true
            default:
                continue
            }
        }
        for (videoId, oldState) in old where new[videoId] == nil {
            if case .completed = oldState { return true }
        }
        return false
    }

    private func cancelAllActiveDownloads() {
        for (videoId, state) in downloads {
            if case .downloading = state {
                cancelledDownloadIds.insert(videoId)
            }
        }
        for (videoId, session) in activeFFmpegSessions {
            cancelledDownloadIds.insert(videoId)
            session.cancel()
        }
        activeFFmpegSessions.removeAll()
    }

    func progressBox(for videoId: String) -> DownloadProgressBox {
        if let box = progressBoxes[videoId] { return box }
        let box = DownloadProgressBox()
        progressBoxes[videoId] = box
        return box
    }

    private func clearProgress(for videoId: String) {
        lastReportedProgress.removeValue(forKey: videoId)
        lastProgressTime.removeValue(forKey: videoId)
        progressBoxes[videoId]?.fraction = 0
    }

    private func setProgress(_ fraction: Double, for videoId: String) {
        let clamped = min(0.99, max(0, fraction))
        let last = lastReportedProgress[videoId] ?? -1
        guard clamped >= 0.99 || last < 0 || clamped - last >= 0.02 else { return }
        // Cap the published bar to ~5 Hz; the per-id box re-renders only the
        // one row, while the coarse `.downloading` state stays in `downloads`.
        if clamped < 0.99 {
            let now = CACurrentMediaTime()
            if now - (lastProgressTime[videoId] ?? 0) < 0.2 { return }
            lastProgressTime[videoId] = now
        }
        lastReportedProgress[videoId] = clamped
        if case .downloading = (downloads[videoId] ?? .notStarted) {
            // already flagged as downloading
        } else {
            downloads[videoId] = .downloading(0)
        }
        progressBox(for: videoId).fraction = clamped
    }

    private func prefetchArtwork(for song: SongItem) async -> Data? {
        if !MusicPlaybackIdentity.isExternal(song.videoId),
           song.contentKind == nil || song.contentKind == .music {
            let artist = cleanArtistDisplay(song.artists.first?.name ?? "")
            if !artist.isEmpty,
               let metadata = await MetadataResolver.enrich(title: song.title, artist: artist, album: song.album) {
                func identity(_ text: String) -> String {
                    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                        .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
                }
                if identity(metadata.title) == identity(song.title),
                   identity(metadata.artist) == identity(artist),
                   let artwork = await prefetchArtwork(from: metadata.artworkURL?.absoluteString) {
                    return artwork
                }
            }
        }
        return await prefetchArtwork(from: song.thumbnailUrl)
    }

    private func prefetchArtwork(from thumbnailUrl: String?) async -> Data? {
        guard let thumbUrl = ArtworkURLs.highRes(thumbnailUrl),
              let url = URL(string: thumbUrl) else { return nil }
        guard let image = try? await ArtworkLoader.image(for: url) else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }

    // MARK: - File Transfer (ffmpeg)

    private func downloadToFile(
        from url: URL,
        to destination: URL,
        videoId: String
    ) async throws {
        guard let caPath = Bundle.main.path(forResource: "cacert", ofType: "pem") else {
            throw NSError(
                domain: "DownloadManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "CA certificate bundle not found"]
            )
        }

        let args = [
            "-y",
            "-rw_timeout", "30000000",
            "-cafile", caPath,
            "-headers", "User-Agent: Mozilla/5.0\r\n",
            "-i", url.absoluteString,
            "-c", "copy",
            destination.path
        ]

        try await runFFmpeg(arguments: args, videoId: videoId) { [weak self] size in
            // The bridge delivers progress on MainActor already.
            // Asymptotic map so unknown Content-Length still moves the bar.
            let fraction = 0.05 + 0.80 * (1 - exp(-Double(size) / 5_000_000))
            self?.setProgress(fraction, for: videoId)
        }
    }

    /// Runs FFmpeg off the main actor via the async API; optionally reports size
    /// stats. Cancelling the calling task also cancels the FFmpeg session.
    private func runFFmpeg(
        arguments: [String],
        videoId: String? = nil,
        onSize: (@MainActor @Sendable (Int64) -> Void)? = nil
    ) async throws {
        let sessionBox = FFmpegSessionBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let session = Self.startFFmpeg(
                    arguments: arguments,
                    continuation: continuation,
                    sessionBox: sessionBox,
                    onSize: onSize,
                    onCompletion: { [weak self] _ in
                        guard let self, let videoId else { return }
                        self.activeFFmpegSessions.removeValue(forKey: videoId)
                    }
                )
                sessionBox.set(session)
                // Register synchronously on MainActor, before the completion
                // task can remove it. A previous session cannot remove its successor.
                if let videoId, let session {
                    activeFFmpegSessions[videoId] = session
                }
                if Task.isCancelled { session?.cancel() }
            }
        } onCancel: {
            sessionBox.current?.cancel()
        }
    }

    /// Objective-C invokes these blocks on its worker queues. Creating them
    /// inside the MainActor-isolated method above makes Swift 6 assert actor
    /// isolation on callback entry, before even an inner Task can hop actors.
    nonisolated private static func startFFmpeg(
        arguments: [String],
        continuation: CheckedContinuation<Void, Error>,
        sessionBox: FFmpegSessionBox,
        onSize: (@MainActor @Sendable (Int64) -> Void)?,
        onCompletion: @escaping @MainActor @Sendable (Int?) -> Void
    ) -> FFmpegSession? {
        let lock = NSLock()
        var finished = false
        let finish: (Result<Void, Error>) -> Void = { result in
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            continuation.resume(with: result)
        }

        let session = FFmpegKit.execute(
            withArgumentsAsync: arguments,
            withCompleteCallback: { session in
                sessionBox.set(nil)
                Task { @MainActor in onCompletion(nil) }
                let rc = session?.getReturnCode()
                if ReturnCode.isSuccess(rc) {
                    finish(.success(Void()))
                } else if ReturnCode.isCancel(rc) {
                    finish(.failure(CancellationError()))
                } else {
                    let output = session?.getOutput() ?? "unknown"
                    Log.downloadManager.debug("FFmpeg output: \(output)")
                    finish(.failure(NSError(
                        domain: "DownloadManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "FFmpeg processing failed"]
                    )))
                }
            },
            withLogCallback: nil,
            withStatisticsCallback: { statistics in
                guard let statistics else { return }
                let size = Int64(statistics.getSize())
                // Pass only the numeric snapshot across the actor boundary,
                // never FFmpeg's non-Sendable Statistics object.
                Task { @MainActor in onSize?(size) }
            }
        )
        if session == nil {
            finish(.failure(NSError(
                domain: "DownloadManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not start audio processing"]
            )))
        }
        return session
    }

}

// MARK: - Delete & queries

extension DownloadManager {
    func delete(videoId: String) async {
        cancelledDownloadIds.insert(videoId)
        if let session = activeFFmpegSessions.removeValue(forKey: videoId) {
            session.cancel()
        }
        clearProgress(for: videoId)
        downloads[videoId] = .notStarted
        tracksById.removeValue(forKey: videoId)

        if let entity = try? await DatabaseService.shared.fetchOne(DownloadedTrackEntity.self, key: videoId) {
            if let url = resolvedURL(for: entity) {
                try? fileManager.removeItem(at: url)
            }
            _ = try? await DatabaseService.shared.delete(entity)
        }
        // Also remove any orphaned file matching this id.
        let scannedFiles = await Self.scanDownloads(downloadsDir)
        if let scanned = scannedFiles[videoId] {
            try? fileManager.removeItem(at: scanned)
        }

        apply(tracksById)
    }

    func deleteAll() async {
        cancelAllActiveDownloads()

        // Remove files directly (off-main) so orphaned downloads are cleaned too.
        let scanned = await Self.scanDownloads(downloadsDir)
        let urls = Array(scanned.values)
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            for url in urls { try? fm.removeItem(at: url) }
        }.value
        // One DELETE instead of a round-trip per downloaded row.
        try? await DatabaseService.shared.write { db in
            try db.execute(sql: "DELETE FROM downloaded_track")
        }

        tracksById.removeAll()
        downloads.removeAll()
        // Keep cancelledDownloadIds so in-flight download(song:) ops still see cancel.
        lastReportedProgress.removeAll()
        apply([:])
    }

    // MARK: - Local URL Resolution

    func localURL(for videoId: String) async -> URL? {
        if let track = tracksById[videoId], let url = resolvedURL(for: track) {
            repairStoredPathIfNeeded(track, url: url)
            return url
        }

        guard let entity = try? await DatabaseService.shared.fetchOne(
            DownloadedTrackEntity.self,
            key: videoId
        ) else {
            Log.downloadManager.debug("localURL: no DB entity for \(videoId)")
            return nil
        }

        guard let url = resolvedURL(for: entity) else {
            Log.downloadManager.debug("localURL: \(videoId) file not found (stored=\(entity.localPath))")
            return nil
        }

        var fixed = entity
        fixed.localPath = storedPath(for: url)
        tracksById[fixed.id] = fixed
        if fixed.localPath != entity.localPath {
            try? await DatabaseService.shared.save(fixed)
        }
        apply(tracksById)
        return url
    }

    private func repairStoredPathIfNeeded(_ track: DownloadedTrackEntity, url: URL) {
        let current = storedPath(for: url)
        guard track.localPath != current else { return }
        var fixed = track
        fixed.localPath = current
        tracksById[fixed.id] = fixed
        apply(tracksById)
        Task { try? await DatabaseService.shared.save(fixed) }
    }

    // MARK: - Query Helpers

    func isDownloaded(videoId: String) -> Bool {
        tracksById[videoId] != nil
    }

    func fetchAll() async -> [DownloadedTrackEntity] {
        Array(tracksById.values)
    }

    func fetchAllSorted() async -> [DownloadedTrackEntity] {
        tracks
    }

    private func fetchAllFromDatabase() async -> [DownloadedTrackEntity] {
        (try? await DatabaseService.shared.fetchAll(DownloadedTrackEntity.self)) ?? []
    }

    var activeDownloads: [(videoId: String, progress: Double)] {
        downloads.compactMap { videoId, state in
            if case .downloading = state {
                return (videoId, progressBoxes[videoId]?.fraction ?? 0)
            }
            return nil
        }
        .sorted { $0.progress > $1.progress }
    }

    func totalStorageBytes() async -> Int64 {
        let dir = downloadsDir
        let tracks = Array(tracksById.values)
        return await Task.detached(priority: .utility) {
            let fm = FileManager.default
            var total: Int64 = 0
            for track in tracks {
                let url = track.localPath.hasPrefix("/")
                    ? URL(fileURLWithPath: track.localPath)
                    : dir.appendingPathComponent(track.localPath)
                guard fm.fileExists(atPath: url.path) else { continue }
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return total
        }.value
    }

    func state(for videoId: String) -> DownloadState {
        if let state = downloads[videoId], state != .notStarted {
            return state
        }
        return tracksById[videoId] != nil ? .completed : .notStarted
    }

    private func ffmpegMetadataArgs(title: String, artist: String) -> [String] {
        ["-metadata", "title=\(title)", "-metadata", "artist=\(artist)"]
    }

    private func writeTempArtwork(_ data: Data?) throws -> URL? {
        guard let data else { return nil }
        let url = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    /// Uses ffmpeg to remux an existing AAC file with metadata (title/artist/artwork).
    /// `-c copy` avoids re-encoding — just copies the audio stream and injects metadata atoms.
    private func attachMetadata(
        to fileURL: URL,
        title: String,
        artist: String,
        artworkData: Data?,
        videoId: String
    ) async throws {
        let ext = fileURL.pathExtension.lowercased() == "flac" ? "flac" : "m4a"
        let tempOutput = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        let artworkURL = try writeTempArtwork(artworkData)
        defer {
            try? fileManager.removeItem(at: tempOutput)
            if let artworkURL {
                try? fileManager.removeItem(at: artworkURL)
            }
        }

        var args = ["-y", "-i", fileURL.path]
        if let artworkURL {
            args += [
                "-i", artworkURL.path,
                "-map", "0:a",
                "-map", "1",
                "-c:a", "copy",
                "-c:v", "mjpeg",
                "-disposition:v", "attached_pic"
            ]
        } else {
            args += ["-c", "copy"]
        }
        args += ffmpegMetadataArgs(title: title, artist: artist)
        args.append(tempOutput.path)

        try await runFFmpeg(arguments: args, videoId: videoId)
        try? fileManager.removeItem(at: fileURL)
        try fileManager.moveItem(at: tempOutput, to: fileURL)
    }

    /// Transcodes a non-AAC stream (Opus, etc.) to AAC with metadata using ffmpeg.
    private func processAudio(_ request: TranscodeRequest, videoId: String, quality: DownloadQuality) async throws {
        guard let bitrate = Self.transcodeBitrate(for: quality) else {
            throw DownloadError.losslessUnavailable
        }
        let tempOutput = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let artworkURL = try writeTempArtwork(request.artworkData)
        defer {
            try? fileManager.removeItem(at: tempOutput)
            if let artworkURL {
                try? fileManager.removeItem(at: artworkURL)
            }
        }

        var args = ["-y", "-i", request.inputURL.path]
        if let artworkURL {
            args += [
                "-i", artworkURL.path,
                "-map", "0:a",
                "-map", "1",
                "-c:a", "aac",
                "-b:a", "\(bitrate)",
                "-c:v", "mjpeg",
                "-disposition:v", "attached_pic"
            ]
        } else {
            args += ["-c:a", "aac", "-b:a", "\(bitrate)"]
        }
        args += ffmpegMetadataArgs(title: request.title, artist: request.artist)
        args.append(tempOutput.path)

        try await runFFmpeg(arguments: args, videoId: videoId)
        try? fileManager.removeItem(at: request.outputURL)
        try fileManager.moveItem(at: tempOutput, to: request.outputURL)
    }

    private struct TranscodeRequest {
        let inputURL: URL
        let outputURL: URL
        let title: String
        let artist: String
        let artworkData: Data?
    }
}

enum DownloadError: Error, LocalizedError {
    case invalidStreamURL
    case transcodeFailed
    case losslessUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidStreamURL:
            return "The stream URL returned by the server was invalid"
        case .transcodeFailed:
            return "Could not convert this track for offline playback."
        case .losslessUnavailable:
            return "Lossless is unavailable for this track from your configured sources. Try another download quality."
        }
    }
}

// MARK: - Environment

private struct DownloadManagerEnvironmentKey: EnvironmentKey {
    static var defaultValue: DownloadManager {
        MainActor.assumeIsolated { DownloadManager.shared }
    }
}

extension EnvironmentValues {
    var downloadManager: DownloadManager {
        get { self[DownloadManagerEnvironmentKey.self] }
        set { self[DownloadManagerEnvironmentKey.self] = newValue }
    }
}


/// Lets the cancellation handler reach the FFmpeg session created inside the
/// continuation without sharing non-Sendable state unsafely.
private final class FFmpegSessionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var session: FFmpegSession?

    func set(_ session: FFmpegSession?) {
        lock.lock()
        self.session = session
        lock.unlock()
    }

    var current: FFmpegSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }
}
