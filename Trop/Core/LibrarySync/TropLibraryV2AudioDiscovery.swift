import Foundation

/// Discover candidate audio by music metadata from providers already used by
/// Trop Search. No YouTube catalogue call, no login, no writes, no autoplay.
/// The user must approve the exact resulting provider track before linking.
@MainActor
enum TropLibraryV2AudioDiscovery {
    static func find(
        for recording: TropLibraryV2Store.RecordingSummary,
        requiresLossless: Bool
    ) async -> [MusicCatalogTrack] {
        guard let artist = recording.artist,
              !TextMatch.normalizeArtist(artist).isEmpty,
              !TextMatch.recordingTitle(recording.title).isEmpty else {
            return []
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
                        return MusicCatalogTrack(
                            id: MusicCatalogID(source: .addon, rawValue: encoded),
                            title: title, artist: performer,
                            durationSeconds: item.durationSeconds ?? 0,
                            artworkURL: item.poster, permalinkURL: nil,
                            isStreamable: true
                        )
                    }
                }
            }
            for await tracks in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                found.append(contentsOf: tracks.filter {
                    TropLibraryV2AudioMatchPolicy.accepts(
                        title: recording.title,
                        artist: artist,
                        durationSeconds: recording.durationSeconds,
                        track: $0,
                        requiresLossless: requiresLossless
                    )
                })
            }
        }
        guard !Task.isCancelled else { return [] }
        // Stable provider order makes results predictable across searches.
        let priority: [MusicCatalogSource] = [
            .addon, .qobuz, .audius, .jiosaavn
        ]
        var unique = Set<MusicCatalogID>()
        return found.filter { unique.insert($0.id).inserted }
            .sorted {
                let a = priority.firstIndex(of: $0.id.source) ?? priority.count
                let b = priority.firstIndex(of: $1.id.source) ?? priority.count
                if a != b { return a < b }
                return $0.id.rawValue < $1.id.rawValue
            }
            .prefix(20)
            .map { $0 }
    }
}
