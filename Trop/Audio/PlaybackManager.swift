//
//  PlaybackManager.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

/// Resolves streams and hands off to PlayerController, trying the client fallback chain.
actor PlaybackManager {
    static let shared = PlaybackManager()

    private var inflightResolutions: [String: Task<PlaybackResult, Error>] = [:]

    private func resolutionKey(videoId: String, forDownload: Bool) -> String {
        forDownload ? "\(videoId):download" : "\(videoId):resolve"
    }

    /// Playback resolution must never share an in-flight entry with a bare
    /// `resolve(...)` (preload/Top-100 warmup), because that task never calls
    /// `play()` — awaiting it would return a result without starting audio.
    private func playKey(videoId: String) -> String {
        "\(videoId):play"
    }

    private init() {}

    /// Audius uses its own full-track streaming endpoint and never passes a
    /// provider-prefixed ID to the YouTube stream resolver.
    private func resolveAudius(videoId: String, song fallbackSong: SongItem? = nil) async throws -> PlaybackResult {
        guard let identifier = MusicCatalogID(storageKey: videoId),
              identifier.source == .audius else {
            throw MusicCatalogError.unavailableTrack
        }
        guard let song = await songForResolve(videoId, fallback: fallbackSong) else {
            throw MusicCatalogError.unavailableTrack
        }
        let sourceTrack = MusicCatalogTrack(
            id: identifier,
            title: song.title,
            artist: song.artistNamesDisplay,
            durationSeconds: song.duration,
            artworkURL: song.thumbnailUrl.flatMap(URL.init(string:)),
            permalinkURL: nil,
            isStreamable: true
        )
        let streamURL = try AudiusClient().streamURL(for: sourceTrack)
        return PlaybackResult(
            streamUrl: streamURL.absoluteString,
            itag: 0,
            mimeType: "audio/mpeg",
            bitrate: 0,
            audioQuality: "audius",
            videoId: videoId,
            title: song.title,
            author: sourceTrack.artist,
            duration: song.duration,
            expiresInSeconds: 0,
            clientName: "audius",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
    }

    /// Qobuz uses fresh, authorized, short-lived FLAC links. Its IDs must
    /// never enter the YouTube stream resolver.
    private func resolveQobuz(videoId: String, song fallbackSong: SongItem? = nil) async throws -> PlaybackResult {
        guard let identifier = MusicCatalogID(storageKey: videoId),
              identifier.source == .qobuz else {
            throw QobuzError.invalidTrack
        }
        guard let song = await songForResolve(videoId, fallback: fallbackSong) else {
            throw QobuzError.invalidTrack
        }
        guard let credentials = try await QobuzCredentialStore.shared.load() else {
            throw QobuzError.notConfigured
        }
        let streamURL = try await QobuzClient().streamURL(
            trackId: identifier.rawValue, credentials: credentials
        )
        return PlaybackResult(
            streamUrl: streamURL.absoluteString,
            itag: 0,
            mimeType: "audio/flac",
            bitrate: 0,
            audioQuality: "qobuz-cd",
            videoId: videoId,
            title: song.title,
            author: song.artistNamesDisplay,
            duration: song.duration,
            expiresInSeconds: 0,
            clientName: "qobuz",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
    }

    /// PencariMusic was removed from the app; ids saved by older versions are
    /// resolved by the installed add-ons using the track metadata.
    private func resolveLegacyPencari(videoId: String, song fallbackSong: SongItem? = nil) async throws -> PlaybackResult {
        guard let song = await songForResolve(videoId, fallback: fallbackSong) else {
            throw MusicCatalogError.unavailableTrack
        }
        guard let preference = addonPreference else { throw MusicCatalogError.unavailableTrack }
        guard let match = await AddonSourceResolver.bestMatch(
                  for: song,
                  requireCD: preference.requireCD,
                  preferAtmos: preference.preferAtmos,
                  preferHiRes: preference.preferHiRes
              ),
              case .url(let url) = match.stream.kind,
              let finalURL = await Self.verifiedStreamURL(url.absoluteString) else {
            throw MusicCatalogError.unavailableTrack
        }
        if let name = await addonName(for: match.track.installationKey) {
            resolvedSourceNames[videoId] = name
        }
        let quality: String
        switch match.stream.qualityTier {
        case "Atmos": quality = "addon-atmos"
        case "Lossless": quality = match.stream.isHiRes ? "addon-hi-res" : "addon-cd"
        default: quality = "addon-\(match.stream.qualityTier.lowercased())"
        }
        return PlaybackResult(
            streamUrl: finalURL.absoluteString,
            itag: 0,
            mimeType: match.stream.mimeType,
            bitrate: match.stream.bitrate,
            audioQuality: quality,
            videoId: videoId,
            title: song.title,
            author: song.artistNamesDisplay,
            duration: song.duration,
            expiresInSeconds: 0,
            clientName: "addon",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
    }

    /// JioSaavn resolves to a decrypted (usually 320 kbps AAC) URL.
    private func resolveJioSaavn(videoId: String, song fallbackSong: SongItem? = nil) async throws -> PlaybackResult {
        guard let identifier = MusicCatalogID(storageKey: videoId),
              identifier.source == .jiosaavn else {
            throw MusicCatalogError.unavailableTrack
        }
        guard let song = await songForResolve(videoId, fallback: fallbackSong) else {
            throw MusicCatalogError.unavailableTrack
        }
        let streamURL = try await JioSaavnClient().resolveStreamURL(for: identifier.rawValue)
        let ext = streamURL.pathExtension.lowercased()
        let mime: String
        let quality: String
        switch ext {
        case "mp3": mime = "audio/mpeg"; quality = "jiosaavn-320-mp3"
        case "aac": mime = "audio/aac"; quality = "jiosaavn-320-aac"
        default: mime = "audio/mp4"; quality = "jiosaavn-320"
        }
        return PlaybackResult(
            streamUrl: streamURL.absoluteString,
            itag: 0,
            mimeType: mime,
            bitrate: 320_000,
            audioQuality: quality,
            videoId: videoId,
            title: song.title,
            author: song.artistNamesDisplay,
            duration: song.duration,
            expiresInSeconds: 0,
            clientName: "jiosaavn",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
    }

    /// Queue metadata for a track that isn't necessarily playing (downloads
    /// from a list pass their own SongItem).
    private func songForResolve(_ videoId: String, fallback: SongItem?) async -> SongItem? {
        if let fallback { return fallback }
        return await queueSong(for: videoId)
    }

    /// Reads a Stremio music addon: resolves the stream URL and maps its
    /// declared quality into the player badge.
    private func resolveAddon(videoId: String, song fallbackSong: SongItem? = nil) async throws -> PlaybackResult {
        guard let ref = AddonPlaybackID.decode(videoId),
              let installation = await MainActor.run(body: {
                  MusicAddonsStore.shared.installation(key: ref.k)
              }) else {
            throw MusicCatalogError.unavailableTrack
        }
        guard let song = await songForResolve(videoId, fallback: fallbackSong) else {
            throw MusicCatalogError.unavailableTrack
        }
        let client = try MusicAddonClient(installation: installation)
        let mode = SettingsStore.shared.musicQualityMode
        let atmos = mode == .auto && SettingsStore.shared.preferAtmos
        let streamQuality: AddonStreamQuality = atmos
            ? .max
            : (mode == .cd ? .lossless : (SettingsStore.shared.preferHiRes ? .hires : .lossless))
        let stream = try await client.resolveStream(
            type: ref.t,
            id: ref.i,
            preferAtmos: atmos,
            quality: streamQuality
        )
        guard !stream.isEncrypted else { throw MusicCatalogError.unavailableTrack }
        resolvedSourceNames[videoId] = installation.manifest.name

        if case .youtube(let youTubeId) = stream.kind {
            var request = StreamResolveRequest.playback(videoId: youTubeId)
            request.options.audioQuality = SettingsStore.shared.audioQuality
            let resolved = try await StreamFallback.resolveFirstValid(
                request, using: InnerTubeClient.tropShared, providers: .tropLive
            )
            return PlaybackResult(
                streamUrl: resolved.streamUrl,
                itag: resolved.itag,
                mimeType: resolved.mimeType,
                bitrate: resolved.bitrate,
                audioQuality: resolved.audioQuality,
                videoId: videoId,
                title: song.title,
                author: song.artistNamesDisplay,
                duration: song.duration,
                expiresInSeconds: resolved.expiresInSeconds,
                clientName: "addon",
                musicVideoType: nil,
                hasVideoContent: false,
                muxedStreamUrl: nil,
                loudnessDb: nil
            )
        }

        guard case .url(let url) = stream.kind else {
            throw MusicCatalogError.unavailableTrack
        }
        let quality: String
        if stream.qualityTier == "Lossless" {
            quality = stream.isHiRes ? "hi-res" : "cd"
        } else {
            quality = stream.qualityTier.lowercased()
        }
        return PlaybackResult(
            streamUrl: url.absoluteString,
            itag: 0,
            mimeType: stream.mimeType,
            bitrate: stream.bitrate,
            audioQuality: "addon-\(quality)",
            videoId: videoId,
            title: song.title,
            author: song.artistNamesDisplay,
            duration: song.duration,
            expiresInSeconds: 0,
            clientName: "addon",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
    }

    // MARK: - Automatic lossless upgrade

    /// Prefetched FLAC resolutions keyed by the YouTube videoId they upgrade.
    private var upgradeResultCache: [String: (result: PlaybackResult, at: Date)] = [:]
    private var upgradePrefetchInFlight: Set<String> = []
    private var resolvedSourceNames: [String: String] = [:]

    private struct AddonQualityPreference: Sendable {
        let requireCD: Bool
        let preferHiRes: Bool
        let preferAtmos: Bool
    }

    /// What the add-ons should look for. Nil means no add-ons (or no upgrade).
    private var addonPreference: AddonQualityPreference? {
        guard SettingsStore.shared.hasMusicAddons else { return nil }
        switch SettingsStore.shared.musicQualityMode {
        case .off:
            return nil
        case .cd:
            return AddonQualityPreference(requireCD: true, preferHiRes: false, preferAtmos: false)
        case .lossless:
            return AddonQualityPreference(
                requireCD: false,
                preferHiRes: SettingsStore.shared.preferHiRes,
                preferAtmos: false
            )
        case .auto, .high:
            return AddonQualityPreference(
                requireCD: false,
                preferHiRes: SettingsStore.shared.preferHiRes,
                preferAtmos: SettingsStore.shared.preferAtmos
            )
        }
    }

    /// Only ever returns an *already prefetched* FLAC, so the play path never
    /// touches the network for lossless. Misses go straight to YouTube.
    private func cachedUpgrade(videoId: String) -> (result: PlaybackResult, age: TimeInterval)? {
        guard !MusicPlaybackIdentity.isExternal(videoId) else { return nil }
        guard let cached = upgradeResultCache[videoId] else { return nil }
        let age = Date().timeIntervalSince(cached.at)
        guard age < upgradeTTL(for: cached.result) else { return nil }
        let acceptable: Bool
        if let preference = addonPreference {
            acceptable = Self.resultMatches(cached.result, preference: preference)
        } else {
            acceptable = SettingsStore.shared.audioQuality == .jiosaavn
                && cached.result.audioQuality.lowercased().contains("jiosaavn")
        }
        guard acceptable else { return nil }
        return (cached.result, age)
    }

    private func prefetchedUpgrade(videoId: String) -> PlaybackResult? {
        cachedUpgrade(videoId: videoId)?.result
    }

    private static func resultMatches(
        _ result: PlaybackResult,
        preference: AddonQualityPreference
    ) -> Bool {
        let quality = result.audioQuality.lowercased()
        if quality.contains("addon-aac") {
            let mode = SettingsStore.shared.musicQualityMode
            return mode == .auto || mode == .high
        }
        if quality.contains("jiosaavn") {
            let mode = SettingsStore.shared.musicQualityMode
            return mode == .auto || mode == .high
        }
        if preference.preferAtmos { return quality.contains("atmos") }
        if quality.contains("atmos") { return false }
        guard isLosslessResult(result) else { return false }
        if isHiResResult(result), !preference.preferHiRes { return false }
        if preference.requireCD, isHiResResult(result) { return false }
        return true
    }

    /// Add-on URLs are minted per request and expire quickly.
    private func upgradeTTL(for result: PlaybackResult) -> TimeInterval { 240 }

    /// Dispatches the prefetch by the user's quality mode. Lossless falls back
    /// to JioSaavn High so an unreachable FLAC origin doesn't leave the user on
    /// Standard.
    private func resolvePreferredUpgrade(
        videoId: String,
        interactive: Bool = false,
        budget: Double? = nil
    ) async -> PlaybackResult? {
        guard let preference = addonPreference else { return nil }
        let cached = upgradeResultCache[videoId].flatMap {
            Date().timeIntervalSince($0.at) < upgradeTTL(for: $0.result) ? $0.result : nil
        }
        if let cached, Self.resultMatches(cached, preference: preference) {
            return cached
        }
        if let lossless = await losslessWithinBudget(
            videoId: videoId,
            seconds: budget ?? (interactive ? 4 : 8),
            preference: preference
        ) {
            return lossless
        }
        let mode = SettingsStore.shared.musicQualityMode
        if mode == .auto || mode == .high {
            // Add-on AAC 320 and JioSaavn 320 cover each other: whichever
            // answers first wins.
            let hasAddonAAC = await MainActor.run {
                MusicAddonsStore.shared.availableAudioCapabilities.aac320
            }
            let fallback = await withTaskGroup(of: PlaybackResult?.self) { group in
                if hasAddonAAC {
                    group.addTask { await self.resolveAddonAAC(videoId: videoId) }
                }
                group.addTask { await self.resolveJioSaavnFallback(videoId: videoId) }
                var first: PlaybackResult?
                for await candidate in group {
                    guard let candidate else { continue }
                    first = candidate
                    break
                }
                group.cancelAll()
                return first
            }
            if let fallback {
                if upgradeResultCache.count >= 100 {
                    upgradeResultCache.removeAll(keepingCapacity: true)
                }
                upgradeResultCache[videoId] = (fallback, Date())
                return fallback
            }
        }
        return nil
    }

    /// The enabled add-ons race for the FLAC; whichever answers first wins.
    private func losslessWithinBudget(
        videoId: String,
        seconds: Double,
        preference: AddonQualityPreference
    ) async -> PlaybackResult? {
        await withTaskGroup(of: PlaybackResult?.self) { group -> PlaybackResult? in
            group.addTask {
                await self.resolveAddonLossless(videoId: videoId, preference: preference)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// JioSaavn 320 fallback: best match by metadata, only when Preferred
    /// Source is Auto (CD/Lossless are explicit FLAC requests).
    private func resolveJioSaavnFallback(videoId: String) async -> PlaybackResult? {
        let mode = SettingsStore.shared.musicQualityMode
        guard mode == .auto || mode == .high else { return nil }
        guard !MusicPlaybackIdentity.isExternal(videoId),
              !MusicPlaybackIdentity.isLegacyPencari(videoId) else { return nil }
        guard let song = await queueSong(for: videoId) else { return nil }
        let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = song.artists.first?.name ?? ""
        let query = artist.isEmpty ? title : "\(artist) \(title)"
        let client = JioSaavnClient()
        guard let tracks = try? await client.search(query: query, limit: 8),
              let best = Self.bestCatalogMatch(tracks, title: title, artist: artist),
              best.isStreamable,
              let url = try? await client.resolveStreamURL(for: best.id.rawValue),
              let finalURL = await Self.verifiedStreamURL(url.absoluteString) else {
            return nil
        }
        resolvedSourceNames[videoId] = "JioSaavn"
        return PlaybackResult(
            streamUrl: finalURL.absoluteString,
            itag: 0,
            mimeType: "audio/mp4",
            bitrate: 320_000,
            audioQuality: "jiosaavn-320",
            videoId: videoId,
            title: song.title,
            author: song.artistNamesDisplay,
            duration: song.duration,
            expiresInSeconds: 0,
            clientName: "jiosaavn",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
    }

    /// AAC 320 fallback from the add-ons.
    private func resolveAddonAAC(videoId: String) async -> PlaybackResult? {
        guard addonPreference != nil else { return nil }
        guard !MusicPlaybackIdentity.isExternal(videoId),
              !MusicPlaybackIdentity.isLegacyPencari(videoId) else { return nil }
        guard let song = await queueSong(for: videoId) else { return nil }
        guard let match = await AddonSourceResolver.bestLossyMatch(for: song),
              case .url(let url) = match.stream.kind,
              let finalURL = await Self.verifiedStreamURL(url.absoluteString) else {
            return nil
        }
        if let name = await addonName(for: match.track.installationKey) {
            resolvedSourceNames[videoId] = name
        }
        return PlaybackResult(
            streamUrl: finalURL.absoluteString,
            itag: 0,
            mimeType: "audio/mp4",
            bitrate: 320_000,
            audioQuality: "addon-aac-320",
            videoId: videoId,
            title: song.title,
            author: song.artistNamesDisplay,
            duration: song.duration,
            expiresInSeconds: 0,
            clientName: "addon",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
    }

    /// Same track as a lossless stream on one of the installed add-ons.
    private func resolveAddonLossless(
        videoId: String,
        preference: AddonQualityPreference
    ) async -> PlaybackResult? {
        guard addonPreference != nil else { return nil }
        guard !MusicPlaybackIdentity.isExternal(videoId) else { return nil }
        guard let song = await queueSong(for: videoId) else { return nil }
        guard let match = await AddonSourceResolver.bestMatch(
                  for: song,
                  requireCD: preference.requireCD,
                  preferAtmos: preference.preferAtmos,
                  preferHiRes: preference.preferHiRes
              ),
              match.stream.qualityTier == "Lossless"
                  || (preference.preferAtmos && match.stream.qualityTier == "Atmos"),
              case .url(let url) = match.stream.kind,
              let finalURL = await Self.verifiedStreamURL(url.absoluteString) else { return nil }
        if let name = await addonName(for: match.track.installationKey) {
            resolvedSourceNames[videoId] = name
        }
        let result = PlaybackResult(
            streamUrl: finalURL.absoluteString,
            itag: 0,
            mimeType: match.stream.mimeType,
            bitrate: match.stream.bitrate,
            audioQuality: match.stream.qualityTier == "Atmos"
                ? "addon-atmos"
                : (match.stream.isHiRes ? "addon-hi-res" : "addon-cd"),
            videoId: videoId,
            title: song.title,
            author: song.artistNamesDisplay,
            duration: song.duration,
            expiresInSeconds: 0,
            clientName: "addon",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
        if upgradeResultCache.count >= 100 {
            upgradeResultCache.removeAll(keepingCapacity: true)
        }
        if resolvedSourceNames.count >= 200 { resolvedSourceNames.removeAll(keepingCapacity: true) }
        upgradeResultCache[videoId] = (result, Date())
        return result
    }

    private static func isLosslessResult(_ result: PlaybackResult) -> Bool {
        losslessLabel(result) != nil
    }

    private static func isHiResResult(_ result: PlaybackResult) -> Bool {
        result.audioQuality.lowercased().contains("hi-res")
    }

    private static func tierRank(_ label: String?) -> Int {
        switch label {
        case "Lossless": return 2
        case "High": return 1
        default: return 0
        }
    }

    /// Optional mid-track upgrade (user setting). Fades out, reloads the better
    /// stream at the same position, fades back in, and updates the badge.
    private func applyUpgradeIfEnabled(_ result: PlaybackResult, videoId: String) async {
        guard SettingsStore.shared.upgradeDuringPlayback else { return }
        let currentVideoId = await MainActor.run { NowPlaying.shared.videoId }
        let isPlaying = await MainActor.run { NowPlaying.shared.isPlaying }
        guard currentVideoId == videoId, isPlaying else { return }
        let position = await MainActor.run { NowPlaying.shared.currentTime }
        let oldLabel = await MainActor.run { NowPlaying.shared.qualityBadgeLabel }
        let oldURL = await MainActor.run { NowPlaying.shared.currentStreamURL }
        let oldLossless = await MainActor.run { NowPlaying.shared.currentLosslessLabel }

        let newLabel = Self.qualityLabel(result)
        guard Self.tierRank(newLabel) > Self.tierRank(oldLabel) else { return }

        // Never cut the current audio for a stream that can't even serve bytes.
        guard await Self.verifyStream(result.streamUrl) else {
            upgradeResultCache[videoId] = nil
            return
        }

        let song = await queueSong(for: videoId)
        let targetVolume = await MainActor.run { SettingsStore.shared.playerVolume }
        await PlayerController.shared.fadeVolume(to: 0, duration: 0.12)
        await PlayerController.shared.play(
            url: result.streamUrl,
            title: song?.title,
            artist: song?.artistNamesDisplay,
            videoId: videoId,
            duration: song.map { TimeInterval($0.duration) },
            artists: song?.artists ?? [],
            thumbnailUrl: song?.thumbnailUrl,
            losslessLabel: Self.losslessLabel(result),
            qualityLabel: newLabel,
            startAt: position
        )
        let upgradeSourceName = sourceName(for: result, videoId: videoId)
        await MainActor.run {
            NowPlaying.shared.currentResult = result
            NowPlaying.shared.currentSourceName = upgradeSourceName
        }
        // Stay muted while the new stream buffers; fade in only once audio is
        // actually advancing. Fading during buffering made it enter abruptly
        // at full volume.
        var started = false
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(50))
            let time = await MainActor.run { NowPlaying.shared.currentTime }
            let currentId = await MainActor.run { NowPlaying.shared.videoId }
            if currentId != videoId { break }
            if time > position + 0.05 { started = true; break }
        }

        if started {
            await PlayerController.shared.fadeVolume(to: targetVolume, duration: 0.35)
            await MainActor.run { PlayerController.shared.setVolumeOverride(nil) }
            return
        }

        // Didn't start: roll back to the previous stream, audible again.
        upgradeResultCache[videoId] = nil
        await MainActor.run { PlayerController.shared.setVolumeOverride(targetVolume) }
        if let oldURL {
            await PlayerController.shared.play(
                url: oldURL,
                title: song?.title,
                artist: song?.artistNamesDisplay,
                videoId: videoId,
                duration: song.map { TimeInterval($0.duration) },
                artists: song?.artists ?? [],
                thumbnailUrl: song?.thumbnailUrl,
                losslessLabel: oldLossless,
                qualityLabel: oldLabel ?? "Standard",
                startAt: position
            )
        }
        await MainActor.run { PlayerController.shared.setVolumeOverride(nil) }
    }

    /// Cheap reachability check: Range request, 200/206, audio-ish content type.
    /// Verifies the stream and returns the **final** URL (after redirects), so
    /// mpv doesn't pay the 307/302 hop again when playback starts.
    private static func verifiedStreamURL(_ urlString: String) async -> URL? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        guard http.statusCode == 200 || http.statusCode == 206 else { return nil }
        if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           !(type.contains("audio")
             || type.contains("flac")
             || type.contains("octet-stream")
             || type.contains("video/mp4")) {
            return nil
        }
        return response.url ?? url
    }

    private static func verifyStream(_ urlString: String) async -> Bool {
        await verifiedStreamURL(urlString) != nil
    }

    /// Boundary-only upgrade: warm this track (for replays) and the next one
    /// so it *starts* in the better source. Never swaps mid-track.
    private func scheduleUpgradePrefetch(videoId: String) {
        Task {
            let upgradesEnabled = SettingsStore.shared.upgradeDuringPlayback
            // With mid-track swaps on, warm the current track first so the swap
            // happens soon. With them off there is nothing to swap: warm the
            // next queue tracks first and keep the current one for later.
            if self.addonPreference != nil, upgradesEnabled {
                let needsFetch = self.upgradeResultCache[videoId] == nil
                if needsFetch {
                    await MainActor.run { NowPlaying.shared.isUpgradingQuality = true }
                }
                let upgraded = await self.resolvePreferredUpgrade(videoId: videoId, interactive: true)
                await MainActor.run { NowPlaying.shared.isUpgradingQuality = false }
                if let upgraded {
                    await self.applyUpgradeIfEnabled(upgraded, videoId: videoId)
                }
            }

            await self.prefetchUpcomingUpgrades(after: videoId, count: 2)
            await self.prefetchNextMetadata(after: videoId)

            if self.addonPreference != nil, !upgradesEnabled,
               self.upgradeResultCache[videoId] == nil {
                // Replay cache for the current track, after the queue is warm.
                _ = await self.resolvePreferredUpgrade(videoId: videoId, budget: 20)
            }
        }
    }

    /// Warms catalogue metadata + album cover for the next queue track.
    private func prefetchNextMetadata(after videoId: String) async {
        let queue = await MainActor.run { NowPlaying.shared.queueSongs }
        guard let index = queue.firstIndex(where: { $0.videoId == videoId }),
              queue.indices.contains(index + 1) else { return }
        let next = queue[index + 1]
        guard !MusicPlaybackIdentity.isExternal(next.videoId) else { return }
        let artist = next.artists.first?.name ?? ""
        _ = await MetadataResolver.enrich(
            title: next.title,
            artist: artist,
            album: next.album,
            duration: next.duration
        )
        if let album = next.album, !album.isEmpty {
            _ = await AlbumCoverStore.shared.coverURL(album: album, artist: artist)
        }
    }

    /// Warms the next two queue tracks while the current one plays, so both
    /// start straight in the better source instead of waiting for the search.
    /// Runs off the play path, sequentially, with a longer budget for the cold
    /// addon lookups.
    private func prefetchUpcomingUpgrades(after videoId: String, count: Int = 2) async {
        let jiosaavnOnly = addonPreference == nil && SettingsStore.shared.audioQuality == .jiosaavn
        guard addonPreference != nil || jiosaavnOnly else { return }
        let queue = await MainActor.run { NowPlaying.shared.queueSongs }
        guard let index = queue.firstIndex(where: { $0.videoId == videoId }) else { return }
        let upcoming = queue.dropFirst(index + 1).prefix(count).map(\.videoId)

        var targets: [String] = []
        for id in upcoming {
            guard !MusicPlaybackIdentity.isExternal(id) else { continue }
            if let cached = upgradeResultCache[id],
               Date().timeIntervalSince(cached.at) < upgradeTTL(for: cached.result) {
                continue
            }
            guard upgradePrefetchInFlight.insert(id).inserted else { continue }
            targets.append(id)
        }

        for id in targets {
            guard !Task.isCancelled else { break }
            // The queue may have moved on while the previous track was warmed.
            let stillUpcoming = await MainActor.run { () -> Bool in
                guard let current = NowPlaying.shared.videoId,
                      let position = NowPlaying.shared.queueSongs.firstIndex(where: { $0.videoId == current }) else {
                    return false
                }
                return NowPlaying.shared.queueSongs
                    .dropFirst(position + 1)
                    .prefix(3)
                    .contains { $0.videoId == id }
            }
            guard stillUpcoming else { continue }
            await MainActor.run { SponsorBlockIntegration.shared.warm(for: id) }
            if addonPreference != nil {
                _ = await resolvePreferredUpgrade(videoId: id, budget: 30)
            } else if let jiosaavn = await resolveJioSaavnFallback(videoId: id) {
                if upgradeResultCache.count >= 100 {
                    upgradeResultCache.removeAll(keepingCapacity: true)
                }
                upgradeResultCache[id] = (jiosaavn, Date())
            }
        }
        upgradePrefetchInFlight.subtract(targets)
    }

    private static func losslessLabel(_ result: PlaybackResult) -> String? {
        let mime = result.mimeType.lowercased()
        let quality = result.audioQuality.lowercased()
        if quality == "addon-hi-res" { return "FLAC · Hi-Res" }
        if quality == "addon-cd" { return "FLAC · CD" }
        if mime == "audio/flac" { return "FLAC" }
        if quality == "qobuz-cd" { return "FLAC · CD" }
        if quality.contains("hi-res") || quality.contains("hires") || quality.contains("24") {
            return "FLAC · Hi-Res"
        }
        if quality.contains("lossless") { return "FLAC" }
        return nil
    }

    /// Lossless always beats lossy. Between lossy sources, the higher bitrate
    /// wins; if YouTube's bitrate is unknown, prefer a known upgrade.
    private static func shouldPreferUpgrade(
        _ upgrade: PlaybackResult,
        over current: PlaybackResult
    ) -> Bool {
        if losslessLabel(upgrade) != nil { return true }
        if losslessLabel(current) != nil { return false }
        let upgradeRate = upgrade.bitrate
        let currentRate = current.bitrate
        if currentRate <= 0 { return upgradeRate > 0 }
        return upgradeRate > currentRate
    }

    /// Badge text is a tier, not a codec: Standard / High / Lossless.
    private static func qualityLabel(_ result: PlaybackResult) -> String? {
        if result.audioQuality.lowercased().contains("atmos") { return "Dolby Atmos" }
        if losslessLabel(result) != nil { return "Lossless" }
        if result.bitrate >= 160_000 { return "High" }
        if result.audioQuality.lowercased().contains("jiosaavn") { return "High" }
        return "Standard"
    }

    private static func normalizedMatchKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s*[\\[(][^\\])]*[\\])]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func bestCatalogMatch(
        _ tracks: [MusicCatalogTrack],
        title: String,
        artist: String
    ) -> MusicCatalogTrack? {
        let key = normalizedMatchKey(title)
        guard !key.isEmpty else { return nil }
        let artistKey = normalizedMatchKey(artist)
        for track in tracks {
            guard normalizedMatchKey(track.title) == key else { continue }
            if artistKey.isEmpty { return track }
            let trackArtist = normalizedMatchKey(track.artist)
            if trackArtist.contains(artistKey) || artistKey.contains(trackArtist) { return track }
        }
        // Exact title is required to avoid upgrading to the wrong song.
        return tracks.first { normalizedMatchKey($0.title) == key }
    }

    /// Plays a downloaded copy if one exists, no matter which source it came
    /// from. Returns nil when the track isn't available offline.
    private func playLocalFile(videoId: String) async -> PlaybackResult? {
        guard let localPath = await DownloadManager.shared.localURL(for: videoId) else { return nil }
        let isFLAC = localPath.pathExtension.lowercased() == "flac"
        let song = await MainActor.run { NowPlaying.shared.queueSongs.first { $0.videoId == videoId } }
        await PlayerController.shared.play(
            url: localPath.absoluteString,
            title: song?.title,
            artist: song?.artists.map(\.name).joined(separator: ", "),
            videoId: videoId,
            duration: song.map { TimeInterval($0.duration) },
            artists: song?.artists ?? [],
            thumbnailUrl: song?.thumbnailUrl,
            losslessLabel: isFLAC ? "FLAC" : nil,
            qualityLabel: isFLAC ? "Lossless" : "Standard"
        )
        await MainActor.run {
            NowPlaying.shared.currentSourceName = "Downloaded"
            NowPlaying.shared.updateVideoAvailability()
        }
        let localResult = PlaybackResult(
            streamUrl: localPath.absoluteString,
            itag: 0,
            mimeType: isFLAC ? "audio/flac" : "audio/mp4",
            bitrate: 0,
            audioQuality: "local",
            videoId: videoId,
            title: song?.title,
            author: song?.artists.map(\.name).joined(separator: ", "),
            duration: song?.duration,
            expiresInSeconds: Int.max,
            clientName: "local",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
        await MainActor.run {
            NowPlaying.shared.currentResult = localResult
        }
        return localResult
    }

    /// Resolve a video and start playback. Returns the result used, or throws.
    @discardableResult
    func resolveAndPlay(videoId: String) async throws -> PlaybackResult {
        // Metadata already switched; stop the previous track so its audio
        // doesn't keep playing while the new stream resolves.
        let previous = await MainActor.run { PlayerController.shared.currentVideoId }
        let isPlaying = await MainActor.run { NowPlaying.shared.isPlaying }
        if isPlaying, let previous, previous != videoId {
            await PlayerController.shared.fadeVolume(to: 0, duration: 0.12)
            await MainActor.run { PlayerController.shared.setPaused(true) }
            await MainActor.run { PlayerController.shared.setVolumeOverride(nil) }
        }
        // Downloaded files win over every network source, including add-ons:
        // an add-on track saved for offline use must play without the addon.
        if let local = await playLocalFile(videoId: videoId) {
            return local
        }
        if MusicPlaybackIdentity.isLegacyPencari(videoId) {
            let result = try await resolveLegacyPencari(videoId: videoId)
            await playNetworkResult(result, videoId: videoId)
            scheduleUpgradePrefetch(videoId: videoId)
            return result
        }
        if MusicPlaybackIdentity.isExternal(videoId) {
            let result: PlaybackResult
            if MusicPlaybackIdentity.isQobuz(videoId) {
                result = try await resolveQobuz(videoId: videoId)
            } else if MusicPlaybackIdentity.isJioSaavn(videoId) {
                result = try await resolveJioSaavn(videoId: videoId)
            } else if MusicPlaybackIdentity.isAddon(videoId) {
                result = try await resolveAddon(videoId: videoId)
            } else {
                result = try await resolveAudius(videoId: videoId)
            }
            let song = await queueSong(for: videoId)
            await PlayerController.shared.play(
                url: result.streamUrl,
                title: song?.title,
                artist: song?.artistNamesDisplay,
                videoId: videoId,
                duration: song.map { TimeInterval($0.duration) },
                artists: song?.artists ?? [],
                thumbnailUrl: song?.thumbnailUrl,
                losslessLabel: Self.losslessLabel(result),
                qualityLabel: Self.qualityLabel(result)
            )
            let externalSourceName = sourceName(for: result, videoId: videoId)
            await MainActor.run {
                NowPlaying.shared.currentSourceName = externalSourceName
                NowPlaying.shared.currentResult = result
            }
            return result
        }
        await MainActor.run { SponsorBlockIntegration.shared.warm(for: videoId) }

        // A prefetched lossless/high stream means the track can start right in
        // the better source instead of resolving YouTube first.
        if SettingsStore.shared.audioQuality == .jiosaavn,
           SettingsStore.shared.musicQualityMode == .auto
               || SettingsStore.shared.musicQualityMode == .high,
           let jiosaavn = await resolveJioSaavnFallback(videoId: videoId) {
            await playNetworkResult(jiosaavn, videoId: videoId)
            scheduleUpgradePrefetch(videoId: videoId)
            return jiosaavn
        }

        if let cached = cachedUpgrade(videoId: videoId) {
            let upgrade = cached.result
            // Prefetch already verified a fresh URL; skipping the extra Range
            // request removes the startup delay on cached lossless.
            var usable = cached.age < 90
            if !usable { usable = await Self.verifyStream(upgrade.streamUrl) }
            if usable {
                await playNetworkResult(upgrade, videoId: videoId)
                scheduleUpgradePrefetch(videoId: videoId)
                return upgrade
            }
            upgradeResultCache[videoId] = nil
        }

        if let cached = await StreamCache.shared.get(videoId: videoId) {
            // A prefetched upgrade can still be better than the cached stream.
            if let upgrade = prefetchedUpgrade(videoId: videoId),
               Self.shouldPreferUpgrade(upgrade, over: cached) {
                if await Self.verifyStream(upgrade.streamUrl) {
                    await playNetworkResult(upgrade, videoId: videoId)
                    scheduleUpgradePrefetch(videoId: videoId)
                    return upgrade
                }
                upgradeResultCache[videoId] = nil
            }
            // Cache contains transport metadata, whose author can be an upload
            // channel. Use the same queue-credit policy as fresh resolutions.
            await playNetworkResult(cached, videoId: videoId)
            scheduleUpgradePrefetch(videoId: videoId)
            return cached
        }

        let key = playKey(videoId: videoId)
        if let existing = inflightResolutions[key] {
            return try await existing.value
        }

        let task = Task { [self] in
            try await resolveAndPlayFromNetwork(videoId: videoId)
        }
        inflightResolutions[key] = task
        defer { clearInflight(key: key) }
        return try await task.value
    }

    /// Runs the client fallback chain for playback. Only called once per
    /// videoId by `resolveAndPlay`, which owns the in-flight dedup entry.
    private func resolveAndPlayFromNetwork(videoId: String) async throws -> PlaybackResult {
        var request = StreamResolveRequest.playback(videoId: videoId)
        request.options.audioQuality = SettingsStore.shared.audioQuality
        let result = try await StreamFallback.resolveFirstValid(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        )
        // If a better source was prefetched, use whichever is higher quality.
        // Lossless always wins; otherwise compare bitrate. The prefetched
        // result is local, so this comparison adds no wait.
        if let upgrade = prefetchedUpgrade(videoId: videoId),
           Self.shouldPreferUpgrade(upgrade, over: result) {
            if await Self.verifyStream(upgrade.streamUrl) {
                await playNetworkResult(upgrade, videoId: videoId)
                scheduleUpgradePrefetch(videoId: videoId)
                return upgrade
            }
            // Dead cached URL (origin rotated/expired): drop it, use YouTube.
            upgradeResultCache[videoId] = nil
        }
        await playNetworkResult(result, videoId: videoId)
        // Warm this track (for replays) and the next two while it plays. Off
        // the play path: never delays audio.
        scheduleUpgradePrefetch(videoId: videoId)
        return result
    }

    private func addonName(for key: String) async -> String? {
        await MainActor.run { MusicAddonsStore.shared.installation(key: key)?.manifest.name }
    }

    private func sourceName(for result: PlaybackResult, videoId: String) -> String {
        // Only credit the add-on when the stream that is actually playing came
        // from it; a cached prefetch name must not mislabel a YouTube stream.
        if result.clientName.lowercased() == "addon",
           let addon = resolvedSourceNames[videoId] {
            return addon
        }
        switch result.clientName.lowercased() {
        case "local": return "Downloaded"
        case "jiosaavn": return "JioSaavn"
        case "qobuz": return "Qobuz"
        case "audius": return "Audius"
        case "addon": return "Add-on"
        default: return "YouTube"
        }
    }

    private func playNetworkResult(_ result: PlaybackResult, videoId: String) async {
        let queueSong = await queueSong(for: videoId)
        let queueArtistName = queueSong.map { artistDisplayString(from: $0.artists) } ?? ""
        let fallbackAuthor = result.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artistName = !queueArtistName.isEmpty ? queueArtistName : fallbackAuthor
        let rawTitle = queueSong?.title ?? result.title ?? ""
        await PlayerController.shared.play(
            url: result.streamUrl,
            title: cleanedTitle(rawTitle, artist: artistName),
            artist: artistName,
            videoId: videoId,
            duration: result.duration.flatMap { $0 > 0 ? TimeInterval($0) : nil },
            artists: queueSong?.artists ?? [],
            loudnessDb: result.loudnessDb,
            thumbnailUrl: queueSong?.thumbnailUrl,
            losslessLabel: Self.losslessLabel(result),
            qualityLabel: Self.qualityLabel(result)
        )
        let sourceName = sourceName(for: result, videoId: videoId)
        await MainActor.run {
            NowPlaying.shared.currentSourceName = sourceName
            NowPlaying.shared.currentResult = result
        }
        await publishVideoAvailability(result: result, videoId: videoId, rowType: queueSong?.musicVideoType)
    }

    private func clearInflight(key: String) {
        inflightResolutions.removeValue(forKey: key)
    }

    /// Queue song for resolve-time metadata (artists, artwork, video type).
    /// One MainActor hop instead of one per field, so the snapshot is
    /// consistent even if the queue changes mid-resolve.
    /// Strips a leading/trailing "Artist - " that YouTube titles often carry so
    /// the player shows just the song name.
    private func cleanedTitle(_ title: String, artist: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return text }
        let lower = text.lowercased()
        let suffix = " - \(name)".lowercased()
        let prefix = "\(name) - ".lowercased()
        if lower.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        } else if lower.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func queueSong(for videoId: String) async -> SongItem? {
        await MainActor.run {
            NowPlaying.shared.queueSongs.first { $0.videoId == videoId }
        }
    }

    /// Publishes video availability for a resolve result. The row type wins
    /// (resolve responses often omit it); unknown rows fall back to an
    /// authoritative lookup inside the shared availability check.
    private func publishVideoAvailability(result: PlaybackResult, videoId: String, rowType: String?) async {
        let type = result.musicVideoType ?? rowType
        let hasVideo = await VideoAvailability.shared.hasVideo(
            videoId: videoId, rowType: rowType, result: result, using: InnerTubeClient.tropShared
        )
        await MainActor.run {
            NowPlaying.shared.updateVideoAvailability(musicVideoType: type, hasVideo: hasVideo)
        }
    }

    /// Resolves a playable video stream URL for video mode. Prefers a muxed
    /// (audio+video) stream; when the video offers none, falls back to an EDL
    /// that combines a DASH video-only stream with a separate audio stream.
    func resolveVideoStream(videoId: String) async throws -> String {
        var request = StreamResolveRequest(videoId: videoId)
        request.options.audioQuality = SettingsStore.shared.audioQuality
        switch try await StreamFallback.resolveVideo(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        ) {
        case .muxed(let url):
            return url
        case .split(let videoURL, let audioURL, let duration):
            return StreamFallback.combineVideoAndAudio(
                videoURL: videoURL,
                audioURL: audioURL,
                duration: duration
            )
        case .hls(let url):
            return url
        }
    }

    /// Returns the muxed/video stream URL for video mode, preferring the cached one.
    func resolveMuxedURL(videoId: String) async throws -> String {
        if let cached = await StreamCache.shared.get(videoId: videoId),
           let muxed = cached.muxedStreamUrl {
            return muxed
        }
        return try await resolveVideoStream(videoId: videoId)
    }

    func resolveVideoOnlyURL(videoId: String) async throws -> String {
        let request = StreamResolveRequest(videoId: videoId)
        switch try await StreamFallback.resolveVideo(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        ) {
        case .muxed(let url):
            return url
        case .split(let videoURL, _, _):
            return videoURL
        case .hls(let url):
            return url
        }
    }

    /// Stable per-launch session id for PoToken minting.
    static let sessionId: String = UUID().uuidString
    /// Resolve a video without playing. Useful for previews / testing.
    func resolve(
        videoId: String,
        preferredFormat: Format? = nil,
        forDownload: Bool = false,
        song: SongItem? = nil
    ) async throws -> PlaybackResult {
        if MusicPlaybackIdentity.isLegacyPencari(videoId) {
            return try await resolveLegacyPencari(videoId: videoId, song: song)
        }
        if MusicPlaybackIdentity.isExternal(videoId) {
            // Every external resolver returns a direct stream URL, so all of
            // them can also be saved for offline playback.
            if MusicPlaybackIdentity.isQobuz(videoId) {
                return try await resolveQobuz(videoId: videoId, song: song)
            }
            if MusicPlaybackIdentity.isJioSaavn(videoId) {
                return try await resolveJioSaavn(videoId: videoId, song: song)
            }
            if MusicPlaybackIdentity.isAddon(videoId) {
                return try await resolveAddon(videoId: videoId, song: song)
            }
            return try await resolveAudius(videoId: videoId, song: song)
        }
        if !forDownload, let cached = await StreamCache.shared.get(videoId: videoId) {
            return cached
        }

        let key = resolutionKey(videoId: videoId, forDownload: forDownload)
        if let existing = inflightResolutions[key] {
            return try await existing.value
        }

        let task = Task { [self] in
            try await resolveFromNetwork(videoId: videoId, preferredFormat: preferredFormat, forDownload: forDownload)
        }
        inflightResolutions[key] = task
        defer { clearInflight(key: key) }
        return try await task.value
    }

    private func resolveFromNetwork(videoId: String, preferredFormat: Format?, forDownload: Bool) async throws -> PlaybackResult {
        var request = forDownload ? StreamResolveRequest.download(videoId: videoId) : .playback(videoId: videoId)
        request.options.preferredFormat = preferredFormat
        request.options.audioQuality = SettingsStore.shared.audioQuality
        request.options.downloadQuality = SettingsStore.shared.downloadQuality
        return try await StreamFallback.resolveFirstValid(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        )
    }
}
