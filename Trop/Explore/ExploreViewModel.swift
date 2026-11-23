//
// ExploreViewModel.swift
// Trop
//
// Created by 686udjie on 11/09/2026.
//

@preconcurrency import SwiftyTube
import Foundation
import SwiftUI

/// Drives the Explore tab (`FEmusic_explore`): new releases, charts,
/// moods & genres.
@MainActor
@Observable
final class ExploreViewModel {

    enum Phase {
        case idle
        case loading
        case loaded
        case empty
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var sections: [ExploreSection] = []
    private(set) var error: Error?

    private var hasLoaded = false

    // MARK: - Loading

    func load() {
        guard !TropLibraryV2AccountIsolation.isEnabled else { return }
        guard !hasLoaded else { return }
        Task { await fetch() }
    }

    func refresh() async {
        guard !TropLibraryV2AccountIsolation.isEnabled else { return }
        await fetch()
    }

    private func fetch() async {
        guard !TropLibraryV2AccountIsolation.isEnabled else {
            sections = []
            phase = .empty
            return
        }
        phase = .loading
        error = nil
        let region = SettingsStore.shared.contentCountry
        Log.explore.debug("Explore fetch start browseId=\(HomePageParser.exploreBrowseId)")
        do {
            let json = try await InnerTubeClient.tropShared.browse(
                browseId: HomePageParser.exploreBrowseId,
                formData: ["selectedValues": [region]]
            ).value
            Log.explore.debug("Explore fetch ok topKeys=\((json.keys.sorted()))")
            guard !TropLibraryV2AccountIsolation.isEnabled else { return }
            sections = HomePageParser.parseExploreSections(from: json)
            await applyRegionalTrending(region: region)
            let moodCount = sections.reduce(0) { $0 + $1.moods.count }
            Log.explore.debug(
                "Explore loaded: " +
                sections.map { "\($0.title)(\($0.kind)):\($0.items.count)" }.joined(separator: ", ") +
                " moods=\(moodCount)"
            )
            phase = sections.isEmpty ? .empty : .loaded
            hasLoaded = phase == .loaded
        } catch {
            Log.explore.error("Explore fetch failed: \(error)")
            self.error = error
            phase = .failed
        }
    }

    /// Swaps the Trending shelf for the region's chart tracks. The explore
    /// carousel follows the IP/account region, which the region setting
    /// cannot move — but per-country charts can, via the country selector.
    /// Falls back to explore's own items on any failure.
    private func applyRegionalTrending(region: String) async {
        guard let index = sections.firstIndex(where: { $0.title.lowercased().contains("trending") }) else {
            Log.explore.debug("Explore: no trending shelf for regional swap")
            return
        }
        guard let playlistId = try? await RegionalCharts.trendingPlaylistId(country: region, using: InnerTubeClient.tropShared),
              let rows = (try? await SyncBridge.playlistDetail.fetchPlaylistRows(playlistId: playlistId))?.rows else { return }
        let songs = rows.compactMap { item -> SongItem? in
            guard let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any] else { return nil }
            return SongItem.from(renderer)
        }
        guard !songs.isEmpty else { return }
        sections[index].items = songs.map(YTItem.song)
        sections[index].kind = .rows
    }

    // MARK: - Moods

    /// Full category page (songs, playlists, videos, albums shelves).
    static func loadMoodDetail(_ mood: MoodItem) async -> [ExploreSection] {
        guard !TropLibraryV2AccountIsolation.isEnabled else { return [] }
        Log.explore.debug("Explore mood '\(mood.title)' fetch params=\(mood.params ?? "none")")
        do {
            let json = try await InnerTubeClient.tropShared.browse(
                browseId: HomePageParser.moodsCategoryBrowseId,
                params: mood.params
            ).value
            let sections = HomePageParser.parseExploreSections(from: json)
            Log.explore.debug(
                "Explore mood '\(mood.title)': " +
                sections.map { "\($0.title)(\($0.kind)):\($0.items.count)" }.joined(separator: ", ")
            )
            return sections
        } catch {
            Log.explore.error("Explore mood '\(mood.title)' failed: \(error)")
            return []
        }
    }

}


/// Explore's explicit artist tap makes a bounded, ephemeral provider search.
/// This does not read InnerTube, persist aliases, build recommendations,
/// fetch streams, or automatically scan the user's whole saved library.
@MainActor
enum ExploreV2ProviderDiscovery {
    static func tracks(for artist: String) async -> [MusicCatalogTrack] {
        guard ExploreV2DiscoveryPolicy.artistSeeds([artist]).count == 1 else {
            return []
        }
        let installs = Array(
            MusicAddonsStore.shared.enabledStremioInstallations.prefix(
                ExploreV2DiscoveryPolicy.maximumAddonInstallations
            )
        )
        let limit = ExploreV2DiscoveryPolicy.resultsPerProvider
        var found: [MusicCatalogTrack] = []
        await withTaskGroup(of: [MusicCatalogTrack].self) { group in
            group.addTask {
                (try? await AudiusClient().searchTracks(
                    query: artist, limit: limit
                )) ?? []
            }
            group.addTask {
                await QobuzCatalogService.shared.searchIfConfigured(
                    query: artist, limit: limit
                )
            }
            group.addTask {
                (try? await JioSaavnClient().search(
                    query: artist, limit: limit
                )) ?? []
            }
            for installation in installs {
                group.addTask {
                    guard let client = try? MusicAddonClient(
                        installation: installation
                    ), let items = try? await client.search(
                        artist, limit: limit
                    ) else { return [] }
                    return items.map { item in
                        var title = item.title
                        var performer = item.artist ?? ""
                        if performer.isEmpty,
                           let split = title.range(of: " - ") {
                            performer = String(title[..<split.lowerBound])
                            title = String(title[split.upperBound...])
                        }
                        let playbackID = AddonPlaybackID.encode(
                            key: item.installationKey,
                            type: item.type, id: item.id
                        )
                        let raw = String(
                            playbackID.dropFirst(AddonPlaybackID.prefix.count)
                        )
                        return MusicCatalogTrack(
                            id: MusicCatalogID(source: .addon, rawValue: raw),
                            title: title, artist: performer,
                            durationSeconds: item.durationSeconds ?? 0,
                            artworkURL: item.poster,
                            permalinkURL: nil, isStreamable: true
                        )
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
        guard !Task.isCancelled else { return [] }

        // Source IDs are meaningful only within the originating provider.
        // Do not merge lookalikes from different addons or editions.
        var seen = Set<MusicCatalogID>()
        let priority: [MusicCatalogSource] = [
            .addon, .qobuz, .audius, .jiosaavn
        ]
        return Array(
            found.filter {
                $0.isStreamable
                    && ExploreV2DiscoveryPolicy.matchesArtist(
                        $0.artist, selected: artist
                    ) && seen.insert($0.id).inserted
            }.sorted {
                let first = priority.firstIndex(of: $0.id.source) ?? 9
                let second = priority.firstIndex(of: $1.id.source) ?? 9
                if first != second { return first < second }
                return $0.id.rawValue < $1.id.rawValue
            }.prefix(ExploreV2DiscoveryPolicy.maximumVisibleTracks)
        )
    }
}
