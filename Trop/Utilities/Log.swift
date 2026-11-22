//
//  Log.swift
//  Trop
//
//  Created by 686udjie on 20/07/2026.
//

import OSLog
@preconcurrency import SwiftyTube

/// Appends log lines to Documents/log.txt (exposed as Trop/log.txt in the
/// Files app) so issues that only show up on-device can be diagnosed without
/// attaching to Xcode. Users can share this file when reporting bugs. The
/// log starts empty once per app process launch, retains one prior session in
/// log.previous.txt for crash recovery, and rotates at ~1 MB.
final class FileLog: @unchecked Sendable {
    static let shared = FileLog()

    private let queue = DispatchQueue(label: "com.686udjie.Trop.FileLog")
    private let maxBytes = 1_000_000
    // Persistent handle + running size avoids a stat + open/close per line.
    // Only touched from `queue`.
    private var handle: FileHandle?
    private var currentSize = 0
    // Queue-confined: an earlier logger can run before TropApp.init, so the
    // first append also prepares the session if startup has not done so yet.
    private var launchPrepared = false

    var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("log.txt")
    }

    private init() {}

    /// One reset per process, not per scene activation or return from background.
    /// Synchronous with pending writes to avoid replacing a live file handle.
    /// If logging happens before TropApp.init, the first append performs the
    /// same reset and this method will not erase those early launch lines.
    func beginNewLaunch() {
        queue.sync {
            guard let url = self.fileURL else { return }
            _ = self.prepareLaunchFileIfNeeded(url)
        }
    }

    /// Runs only on the serial file queue. Close the writer before atomically
    /// replacing the previous process's log, then reopen on first append.
    /// Keep at most one previous session so a crash remains diagnosable after
    /// relaunch without mixing old messages into the fresh log.
    /// Never append to stale log data if the reset failed.
    private func prepareLaunchFileIfNeeded(_ url: URL) -> Bool {
        guard !launchPrepared else { return true }
        try? handle?.close()
        handle = nil

        if let oldLog = try? Data(contentsOf: url), !oldLog.isEmpty {
            let previousURL = url.deletingLastPathComponent()
                .appendingPathComponent("log.previous.txt")
            // A backup failure must not prevent this launch from starting.
            try? oldLog.write(to: previousURL, options: .atomic)
        }
        do {
            try Data().write(to: url, options: .atomic)
            currentSize = 0
            launchPrepared = true
            return true
        } catch {
            return false
        }
    }

    func append(_ category: String, _ level: String, _ message: String) {
        queue.async { [weak self] in
            guard let self, let url = self.fileURL,
                  self.prepareLaunchFileIfNeeded(url) else { return }
            let stamp = Self.formatter.string(from: Date())
            let line = "\(stamp) [\(level)][\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if self.handle == nil {
                self.openHandle(url)
            }

            if self.currentSize > self.maxBytes {
                // Rotate: keep it simple — start a fresh file.
                try? self.handle?.close()
                self.handle = nil
                try? data.write(to: url, options: .atomic)
                self.currentSize = data.count
                self.openHandle(url)
                return
            }

            if let handle = self.handle {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                self.currentSize += data.count
            } else {
                try? data.write(to: url, options: .atomic)
                self.currentSize = data.count
            }
        }
    }

    private func openHandle(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        handle = file
        currentSize = (try? file.seekToEnd()).map { Int($0) } ?? 0
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

struct AppLogger {
    let logger: Logger
    var category: String = ""
    /// mpv streams every internal log line through here — far too chatty to
    /// mirror onto disk.
    var writesToDisk: Bool = true
    var redact: Bool = true

    private func emit(_ level: String, _ message: String) {
        guard writesToDisk else { return }
        FileLog.shared.append(category, level, message)
    }

    func debug(_ message: String) {
        emit("DEBUG", message)
        if redact {
            logger.debug("\(message, privacy: .private)")
        } else {
            logger.debug("\(message)")
        }
    }

    func info(_ message: String) {
        emit("INFO", message)
        if redact {
            logger.info("\(message, privacy: .private)")
        } else {
            logger.info("\(message)")
        }
    }

    func notice(_ message: String) {
        emit("NOTICE", message)
        if redact {
            logger.notice("\(message, privacy: .private)")
        } else {
            logger.notice("\(message)")
        }
    }

    func warning(_ message: String) {
        emit("WARNING", message)
        if redact {
            logger.warning("\(message, privacy: .private)")
        } else {
            logger.warning("\(message)")
        }
    }

    func error(_ message: String) {
        emit("ERROR", message)
        if redact {
            logger.error("\(message, privacy: .private)")
        } else {
            logger.error("\(message)")
        }
    }

    func fault(_ message: String) {
        emit("FAULT", message)
        if redact {
            logger.fault("\(message, privacy: .private)")
        } else {
            logger.fault("\(message)")
        }
    }
}

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.686udjie.Trop"

    static func wireSwiftyTube() {
        guard SwiftyTubeLog.handler == nil else { return }
        let logger = Logger(
            subsystem: subsystem,
            category: "SwiftyTube"
        )
        SwiftyTubeLog.handler = { message, level in
            switch level {
            case .debug:
                logger.debug("\(message, privacy: .private)")
            case .info:
                logger.info("\(message, privacy: .private)")
            case .notice:
                logger.notice("\(message, privacy: .public)")
                FileLog.shared.append("SwiftyTube", "NOTICE", message)
            case .error:
                logger.error("\(message, privacy: .public)")
                FileLog.shared.append("SwiftyTube", "ERROR", message)
            }
        }
    }

    static let player = AppLogger(logger: Logger(subsystem: subsystem, category: "Player"), category: "player", redact: false)
    static let sponsorBlock = AppLogger(logger: Logger(subsystem: subsystem, category: "SponsorBlock"), category: "sponsorBlock", redact: false)
    static let mpv = AppLogger(logger: Logger(subsystem: subsystem, category: "mpv"), category: "mpv", writesToDisk: false, redact: false)
    static let nowPlaying = AppLogger(logger: Logger(subsystem: subsystem, category: "NowPlaying"), category: "nowPlaying")
    static let login = AppLogger(logger: Logger(subsystem: subsystem, category: "Login"), category: "login")
    static let loginViewModel = AppLogger(logger: Logger(subsystem: subsystem, category: "LoginViewModel"), category: "loginViewModel")
    static let db = AppLogger(logger: Logger(subsystem: subsystem, category: "DB"), category: "db")
    static let playlistDetail = AppLogger(logger: Logger(subsystem: subsystem, category: "PlaylistDetail"), category: "playlistDetail")
    static let parser = AppLogger(logger: Logger(subsystem: subsystem, category: "Parser"), category: "parser")
    static let albumDetail = AppLogger(logger: Logger(subsystem: subsystem, category: "AlbumDetail"), category: "albumDetail")
    static let albumDetailViewModel = AppLogger(
        logger: Logger(subsystem: subsystem, category: "AlbumDetailViewModel"), category: "albumDetailViewModel")
    static let artistDetail = AppLogger(logger: Logger(subsystem: subsystem, category: "ArtistDetail"), category: "artistDetail")
    static let podcastDetail = AppLogger(logger: Logger(subsystem: subsystem, category: "PodcastDetail"), category: "podcastDetail")
    static let historyView = AppLogger(logger: Logger(subsystem: subsystem, category: "HistoryView"), category: "historyView")
    static let homeScreenView = AppLogger(logger: Logger(subsystem: subsystem, category: "HomeScreenView"), category: "homeScreenView")
    static let homeViewModel = AppLogger(logger: Logger(subsystem: subsystem, category: "HomeViewModel"), category: "homeViewModel")
    static let explore = AppLogger(logger: Logger(subsystem: subsystem, category: "Explore"), category: "explore")
    static let libraryView = AppLogger(logger: Logger(subsystem: subsystem, category: "LibraryView"), category: "libraryView")
    static let innerTube = AppLogger(logger: Logger(subsystem: subsystem, category: "InnerTube"), category: "innerTube")
    static let playbackState = AppLogger(logger: Logger(subsystem: subsystem, category: "PlaybackState"), category: "playbackState")
    static let registerPlayback = AppLogger(logger: Logger(subsystem: subsystem, category: "RegisterPlayback"), category: "registerPlayback")
    static let search = AppLogger(logger: Logger(subsystem: subsystem, category: "Search"), category: "search")
    static let searchView = AppLogger(logger: Logger(subsystem: subsystem, category: "SearchView"), category: "searchView")
    static let downloadManager = AppLogger(logger: Logger(subsystem: subsystem, category: "DownloadManager"), category: "downloadManager")
    static let sync = AppLogger(logger: Logger(subsystem: subsystem, category: "Sync"), category: "sync")
    static let addSong = AppLogger(logger: Logger(subsystem: subsystem, category: "AddSong"), category: "addSong")
    static let settings = AppLogger(logger: Logger(subsystem: subsystem, category: "Settings"), category: "settings")
    static let lastfm = AppLogger(logger: Logger(subsystem: subsystem, category: "LastFM"), category: "lastfm")
}
