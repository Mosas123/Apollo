import Foundation

/// Discover candidate audio by music metadata from providers already used by
/// Trop Search. No YouTube catalogue call, no login, no writes, no autoplay.
/// Exact-version results may be prelinked by Library V2; alternative versions
/// remain review-only and always require explicit user approval.
@MainActor
enum TropLibraryV2AudioDiscovery {
    static func inspect(
        for recording: TropLibraryV2Store.RecordingSummary,
        requiresLossless: Bool
    ) async -> TropMatchSearchResult {
        guard let artist = recording.artist,
              !TextMatch.normalizeArtist(artist).isEmpty,
              !TextMatch.recordingTitle(recording.title).isEmpty else {
            return TropMatchSearchResult(exact: [], review: [])
        }
        let query = TextMatch.queryArtist(artist)
            + " " + TextMatch.recordingTitle(recording.title)
        let installations = Array(
            MusicAddonsStore.shared.enabledStremioInstallations.prefix(4)
        )
        var found: [MusicCatalogTrack] = []
        await withTaskGroup(of: [MusicCatalogTrack].self) { group in
            group.addTask {
                (try? await AudiusClient().searchTracks(query: query, limit: 20)) ?? []
            }
            group.addTask {
                await QobuzCatalogService.shared.searchIfConfigured(
                    query: query, limit: 20
                )
            }
            group.addTask {
                (try? await JioSaavnClient().search(query: query, limit: 20)) ?? []
            }
            for installation in installations {
                group.addTask {
                    guard let client = try? MusicAddonClient(installation: installation),
                          let tracks = try? await client.search(query, limit: 15)
                    else { return [] }
                    return tracks.map { item in
                        var title = item.title
                        var performer = item.artist ?? ""
                        if performer.isEmpty,
                           let split = title.range(of: " - ") {
                            performer = String(title[..<split.lowerBound])
                            title = String(title[split.upperBound...])
                        }
                        let playbackID = AddonPlaybackID.encode(
                            key: item.installationKey,
                            type: item.type,
                            id: item.id
                        )
                        let encoded = String(
                            playbackID.dropFirst(AddonPlaybackID.prefix.count)
                        )
                        var candidate = MusicCatalogTrack(
                            id: MusicCatalogID(source: .addon, rawValue: encoded),
                            title: title, artist: performer,
                            durationSeconds: item.durationSeconds ?? 0,
                            artworkURL: item.poster, permalinkURL: nil,
                            isStreamable: true
                        )
                        candidate.albumTitle = item.album
                        return candidate
                    }
                }
            }
            for await tracks in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                found.append(contentsOf: tracks)
            }
        }
        guard !Task.isCancelled else {
            return TropMatchSearchResult(exact: [], review: [])
        }
        let priority: [MusicCatalogSource] = [
            .addon, .qobuz, .audius, .jiosaavn
        ]
        var unique = Set<MusicCatalogID>()
        let sorted = found.filter { unique.insert($0.id).inserted }
            .sorted {
                let a = priority.firstIndex(of: $0.id.source) ?? priority.count
                let b = priority.firstIndex(of: $1.id.source) ?? priority.count
                if a != b { return a < b }
                return $0.id.rawValue < $1.id.rawValue
            }
        var exact: [MusicCatalogTrack] = []
        var review: [MusicCatalogTrack] = []
        for track in sorted {
            switch TropMatchCandidatePolicy.classify(
                title: recording.title, artist: recording.artist,
                durationSeconds: recording.durationSeconds,
                track: track, requiresLossless: requiresLossless
            ) {
            case .exact where exact.count < 20: exact.append(track)
            case .review where review.count < 20: review.append(track)
            default: break
            }
        }
        return TropMatchSearchResult(exact: exact, review: review)
    }

    static func find(
        for recording: TropLibraryV2Store.RecordingSummary,
        requiresLossless: Bool
    ) async -> [MusicCatalogTrack] {
        await inspect(for: recording, requiresLossless: requiresLossless).exact
    }
}
