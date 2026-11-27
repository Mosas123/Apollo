//
//  ApolloApp.swift
//  Apollo
//
//  Created by 686udjie on 28/06/2026.
//

import Nuke
import SwiftUI
import UIKit

@main
struct ApolloApp: App {
    @State private var settings = SettingsStore.shared

    init() {
        // New process = clean Documents/log.txt; foreground transitions do not
        // reset it. FileLog also handles any messages emitted before this init.
        FileLog.shared.beginNewLaunch()
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        Log.player.info("APP_LOG_SESSION_START build=\(build)")
        configureNuke()
        configureURLCache()
        ensureDirectories()
        Self.pruneSyncDiagnostics()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Clear the cache actually installed on the pipeline (see
            // configureNuke); `ImageCache.shared` is a different instance.
            ImagePipeline.shared.configuration.imageCache?.removeAll()
            AsyncImageView.clearArtworkCache()
            URLCache.shared.removeAllCachedResponses()
        }
        Log.wireApolloTube()
        PlayerController.registerRemoteControlSupport()
        observePlaybackSettings()
        Task { await InnerTubeClient.apolloShared.syncApolloLocale() }
    }

    /// Re-applies mpv playback settings whenever the user changes the
    /// equalizer or the audio filters from any screen.
    private func observePlaybackSettings() {
        func register() {
            withObservationTracking {
                let settings = SettingsStore.shared
                _ = settings.equalizerEnabled
                _ = settings.equalizerGains
                _ = settings.audioNormalization
                _ = settings.gaplessPlayback
            } onChange: {
                Task { @MainActor in
                    PlayerController.shared.applyPlaybackSettings()
                    register()
                }
            }
        }
        register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(settings.preferredColorScheme)
                .tint(settings.accentColor)
                .environment(settings)
                .environment(\.downloadManager, DownloadManager.shared)
        }
    }

    private func configureNuke() {
        let dataCache = try? DataCache(name: "com.cl0udly.apollo.nuke")
        // 300 MB is plenty for covers and evicts with LRU; 2 GB accumulated too
        // much compared with other players.
        dataCache?.sizeLimit = 200 * 1024 * 1024

        var config = ImagePipeline.Configuration()
        config.dataCache = dataCache
        config.imageCache = ImageCache(costLimit: 64 * 1024 * 1024)

        ImagePipeline.shared = ImagePipeline(configuration: config)
    }

    /// Bounded HTTP cache for API/JSON responses instead of the system default.
    private func configureURLCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            diskPath: "com.cl0udly.apollo.urlcache"
        )
    }

    /// Diagnostic playlist dumps are timestamped and were never deleted. Keep
    /// only the five newest.
    private static func pruneSyncDiagnostics() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("sync-debug", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for url in sorted.dropFirst(5) {
            try? fm.removeItem(at: url)
        }
    }

    private func ensureDirectories() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: docs.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: docs.appendingPathComponent("Player"), withIntermediateDirectories: true)
    }
}
