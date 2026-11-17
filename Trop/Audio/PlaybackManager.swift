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
    private func resolveAudius(videoId: String) async throws -> PlaybackResult {
        guard let identifier = MusicCatalogID(storageKey: videoId),
              identifier.source == .audius,
              let song = await queueSong(for: videoId) else {
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
    private func resolveQobuz(videoId: String) async throws -> PlaybackResult {
        guard let identifier = MusicCatalogID(storageKey: videoId),
              identifier.source == .qobuz,
              let song = await queueSong(for: videoId) else {
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

    /// PencariMusic streams resolve server-side to a short-lived FLAC URL; the
    /// short code must never reach the YouTube resolver.
    private func resolvePencari(videoId: String) async throws -> PlaybackResult {
        guard let identifier = MusicCatalogID(storageKey: videoId),
              identifier.source == .pencari,
              let song = await queueSong(for: videoId) else {
            throw MusicCatalogError.unavailableTrack
        }
        guard let client = await PencariMusicClient.configured() else {
            throw PencariMusicError.notConfigured
        }
        let streamURL = try await client.resolveStreamURL(for: identifier.rawValue)
        return PlaybackResult(
            streamUrl: streamURL.absoluteString,
            itag: 0,
            mimeType: "audio/flac",
            bitrate: 0,
            audioQuality: "pencari-flac",
            videoId: videoId,
            title: song.title,
            author: song.artistNamesDisplay,
            duration: song.duration,
            expiresInSeconds: 0,
            clientName: "pencari",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
    }

    // MARK: - Automatic lossless upgrade

    private var pencariCooldownUntil: Date?
    private var pencariMatchCache: [String: String] = [:]

    /// When the user prefers lossless, tries to find the same track on the
    /// bundled PencariMusic addon and resolve a FLAC stream. Returns nil on any
    /// miss/failure so the caller falls back to YouTube. A short cooldown after
    /// a failure avoids slowing every subsequent play while the origin is down.
    private func resolveLosslessUpgrade(videoId: String) async -> PlaybackResult? {
        guard SettingsStore.shared.preferLosslessAudio else { return nil }
        guard !MusicPlaybackIdentity.isExternal(videoId) else { return nil }
        if let until = pencariCooldownUntil, until > Date() { return nil }
        guard let song = await queueSong(for: videoId) else { return nil }
        let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = song.artists.first?.name ?? ""
        guard let client = await PencariMusicClient.configured() else { return nil }

        let pencariId: String
        if let cached = pencariMatchCache[videoId] {
            pencariId = cached
        } else {
            let query = artist.isEmpty ? title : "\(artist) \(title)"
            let tracks = (try? await client.searchTracks(query: query, limit: 8)) ?? []
            guard let best = Self.bestPencariMatch(tracks, title: title, artist: artist) else { return nil }
            pencariId = best.id.rawValue
            if pencariMatchCache.count >= 500 { pencariMatchCache.removeAll(keepingCapacity: true) }
            pencariMatchCache[videoId] = pencariId
        }

        do {
            let url = try await client.resolveStreamURLFast(for: pencariId)
            return PlaybackResult(
                streamUrl: url.absoluteString,
                itag: 0,
                mimeType: "audio/flac",
                bitrate: 0,
                audioQuality: "pencari-flac",
                videoId: videoId,
                title: song.title,
                author: song.artistNamesDisplay,
                duration: song.duration,
                expiresInSeconds: 0,
                clientName: "pencari",
                musicVideoType: nil,
                hasVideoContent: false,
                muxedStreamUrl: nil,
                loudnessDb: nil
            )
        } catch {
            pencariCooldownUntil = Date().addingTimeInterval(300)
            return nil
        }
    }

    private static func losslessLabel(_ result: PlaybackResult) -> String? {
        let mime = result.mimeType.lowercased()
        let quality = result.audioQuality.lowercased()
        if mime == "audio/flac" || quality == "pencari-flac" { return "FLAC" }
        if quality == "qobuz-cd" { return "FLAC · CD" }
        if quality.contains("hi-res") || quality.contains("hires") || quality.contains("24") {
            return "FLAC · Hi-Res"
        }
        if quality.contains("lossless") { return "FLAC" }
        return nil
    }

    private static func normalizedMatchKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s*[\\[(][^\\])]*[\\])]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func bestPencariMatch(
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

    /// Resolve a video and start playback. Returns the result used, or throws.
    @discardableResult
    func resolveAndPlay(videoId: String) async throws -> PlaybackResult {
        if MusicPlaybackIdentity.isExternal(videoId) {
            let result: PlaybackResult
            if MusicPlaybackIdentity.isQobuz(videoId) {
                result = try await resolveQobuz(videoId: videoId)
            } else if MusicPlaybackIdentity.isPencari(videoId) {
                result = try await resolvePencari(videoId: videoId)
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
                losslessLabel: Self.losslessLabel(result)
            )
            return result
        }
        await MainActor.run { SponsorBlockIntegration.shared.warm(for: videoId) }
        if let localPath = await DownloadManager.shared.localURL(for: videoId) {
            let song = await MainActor.run { NowPlaying.shared.queueSongs.first { $0.videoId == videoId } }
            let artists = song?.artists ?? []
            await PlayerController.shared.play(
                url: localPath.absoluteString,
                title: song?.title,
                artist: song?.artists.map(\.name).joined(separator: ", "),
                videoId: videoId,
                duration: song.map { TimeInterval($0.duration) },
                artists: artists,
                thumbnailUrl: song?.thumbnailUrl,
                losslessLabel: localPath.pathExtension.lowercased() == "flac" ? "FLAC" : nil
            )
            await MainActor.run {
                NowPlaying.shared.updateVideoAvailability()
            }
            return PlaybackResult(
                streamUrl: localPath.absoluteString,
                itag: 0,
                mimeType: "audio/mp4",
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
        }

        if let cached = await StreamCache.shared.get(videoId: videoId) {
            let queueSong = await queueSong(for: videoId)
            await PlayerController.shared.play(
                url: cached.streamUrl,
                title: cached.title,
                artist: cached.author,
                videoId: videoId,
                duration: cached.duration.flatMap { $0 > 0 ? TimeInterval($0) : nil },
                artists: queueSong?.artists ?? [],
                loudnessDb: cached.loudnessDb,
                thumbnailUrl: queueSong?.thumbnailUrl,
                losslessLabel: Self.losslessLabel(cached)
            )
            await publishVideoAvailability(result: cached, videoId: videoId, rowType: queueSong?.musicVideoType)
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
        // Lossless-first: a match on the bundled addon plays FLAC; otherwise we
        // silently continue to the YouTube resolver below.
        if let lossless = await resolveLosslessUpgrade(videoId: videoId) {
            await playNetworkResult(lossless, videoId: videoId)
            return lossless
        }
        var request = StreamResolveRequest.playback(videoId: videoId)
        request.options.audioQuality = SettingsStore.shared.audioQuality
        let result = try await StreamFallback.resolveFirstValid(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        )
        await playNetworkResult(result, videoId: videoId)
        return result
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
            losslessLabel: Self.losslessLabel(result)
        )
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
    func resolve(videoId: String, preferredFormat: Format? = nil, forDownload: Bool = false) async throws -> PlaybackResult {
        if MusicPlaybackIdentity.isExternal(videoId) {
            guard !forDownload else { throw MusicCatalogError.unavailableTrack }
            if MusicPlaybackIdentity.isQobuz(videoId) {
                return try await resolveQobuz(videoId: videoId)
            }
            if MusicPlaybackIdentity.isPencari(videoId) {
                return try await resolvePencari(videoId: videoId)
            }
            return try await resolveAudius(videoId: videoId)
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
