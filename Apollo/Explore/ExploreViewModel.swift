//
// ExploreViewModel.swift
// Apollo
//
// Created by 686udjie on 11/09/2026.
//

@preconcurrency import ApolloTube
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
        guard !hasLoaded else { return }
        Task { await fetch() }
    }

    func refresh() async {
        await fetch()
    }

    private func fetch() async {
        phase = .loading
        error = nil
        do {
            let spotifySections = try await SpotifyHomeService.shared.sections()
            var mapped: [ExploreSection] = []
            for section in spotifySections {
                let kind: ExploreSection.Kind = section.items.allSatisfy { item in
                    if case .song = item { return true }
                    return false
                } ? .rows : .cards
                mapped.append(
                    ExploreSection(
                        title: section.title,
                        kind: kind,
                        items: section.items,
                        moods: []
                    )
                )
            }
            sections = mapped
            phase = sections.isEmpty ? .empty : .loaded
            hasLoaded = phase == .loaded
        } catch {
            Log.explore.error("Explore fetch failed: \(error)")
            self.error = error
            phase = .failed
        }
    }

    // MARK: - Moods

    /// Full category page backed by Spotify search.
    static func loadMoodDetail(_ mood: MoodItem) async -> [ExploreSection] {
        do {
            let results = try await SpotifyCatalogProvider().search(mood.title, limit: 20)
            let items = results.tracks.map { YTItem.song(SpotifyCatalogMapper.song(from: $0)) }
                + results.albums.map { YTItem.album(SpotifyCatalogMapper.album(from: $0)) }
                + results.artists.map { YTItem.artist(SpotifyCatalogMapper.artist(from: $0)) }
                + results.playlists.map { YTItem.playlist(SpotifyCatalogMapper.playlist(from: $0)) }
            guard !items.isEmpty else { return [] }
            return [
                ExploreSection(
                    title: mood.title,
                    kind: .cards,
                    items: items,
                    moods: []
                )
            ]
        } catch {
            Log.explore.error("Explore mood '\(mood.title)' failed: \(error)")
            return []
        }
    }

}
