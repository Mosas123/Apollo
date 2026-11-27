//
//  SearchViewModel.swift
//  Apollo
//
//  Created by 686udjie on 03/07/2026.
//

import Foundation
@preconcurrency import ApolloTube
import SwiftUI

/// Result ordering for the search screen.
enum SearchSort: String, CaseIterable {
    case relevant
    case date
    case recent
    case rating

    var title: String {
        switch self {
        case .relevant: return "Most Relevant"
        case .date: return "Date Released"
        case .recent: return "Recently Played"
        case .rating: return "Rating"
        }
    }
}
/// Drives the search screen.
///
/// Debounced live queries and explicit submissions share cancellation guards.
@MainActor
@Observable
final class SearchViewModel {

    // MARK: - Phase

    enum Phase {
        /// Nothing submitted yet: recent searches / empty state.
        case idle
        /// Fetching results for the submitted query.
        case loading
        /// Showing results for the submitted query.
        case results
        /// Submitted query returned nothing.
        case noResults
        /// Submission failed.
        case failed
    }

    private(set) var phase: Phase = .idle
    /// True only while a network fetch is actually in flight (after the debounce),
    /// so the spinner doesn't flash on every keystroke.
    private(set) var isFetching = false

    // MARK: - Field & results

    /// Live text of the search field.
    var fieldText = "" {
        didSet {
            guard fieldText != oldValue else { return }
            handleFieldTextChange()
        }
    }

    /// Query whose results are currently held (if any).
    private(set) var submittedQuery = ""

    private(set) var results: [SearchSection] = []
    /// Source-specific results never enter YouTube's YTItem parser.
    private(set) var audiusTracks: [MusicCatalogTrack] = []
    private(set) var qobuzTracks: [MusicCatalogTrack] = []
    private(set) var jiosaavnTracks: [MusicCatalogTrack] = []
    private(set) var addonTracks: [MusicCatalogTrack] = []

    // MARK: - Local matches (populated per submission, for Library filter)

    var localSongs: [SongEntity] = []
    var localArtists: [ArtistEntity] = []
    var localAlbums: [AlbumEntity] = []
    var localPlaylists: [PlaylistEntity] = []

    // MARK: - Filtering & sorting

    var selectedSectionFilter: String?
    var isShowingLibrary = false

    /// Active result ordering (persisted).
    var sort: SearchSort {
        didSet {
            guard sort != oldValue else { return }
            UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey)
            if sort == .recent {
                preloadRecencyMap()
            }
        }
    }

    /// Artist hero for artist queries (top result is an artist).
    private(set) var heroArtist: ArtistItem?
    private(set) var heroSongs: [SongItem] = []

    /// Latest play timestamp per videoId, for Recently Played sorting.
    /// Shared across instances — the search view model is recreated on tab
    /// visits, and without this every visit refetched + relogged.
    private static var sharedRecencyMap: [String: Date]?
    private static var recencyFetchInFlight = false
    private var recencyMap: [String: Date]? {
        get { Self.sharedRecencyMap }
        set { Self.sharedRecencyMap = newValue }
    }

    // MARK: - Submission outcome

    var error: Error?

    // MARK: - History

    var searchHistory: [SearchHistoryEntity] = []

    private var fetchTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private(set) var suggestions: [String] = []
    private var suggestionCache: [String: [String]] = [:]
    private var resultCache: [String: [SearchSection]] = [:]
    private var cacheOrder: [String] = []

    private static let historyKey = "Search.history"
    private static let historyNewestFirstKey = "Search.historyNewestFirst"
    private static let sortKey = "Search.sort"
    private static let maxHistoryEntries = 20

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.sortKey)
        sort = SearchSort(rawValue: raw ?? "") ?? .relevant
        loadSearchHistory()
        if sort == .recent {
            preloadRecencyMap()
        }
    }

    // MARK: - Derived content

    /// Canonical display order: songs first, then albums, artists, videos.
    static let displayOrder = ["Songs", "Albums", "Artists", "Videos", "Playlists", "Podcasts", "Episodes"]

    var availableFilters: [String] {
        var filters = ["Library"]
        let titles = Set(results.map(\.title))
        filters.append(contentsOf: Self.displayOrder.filter { titles.contains($0) })
        if !audiusTracks.isEmpty { filters.append("Audius") }
        if !qobuzTracks.isEmpty { filters.append("Qobuz") }
        if !jiosaavnTracks.isEmpty { filters.append("JioSaavn") }
        if !addonTracks.isEmpty { filters.append("Add-ons") }
        return filters
    }

    /// Results ordered for display, with the active sort applied to
    /// Songs/Videos (and Albums for Date Released).
    var displaySections: [SearchSection] {
        let ordered = Self.displayOrder.compactMap { title in
            results.first { $0.title == title }
        } + results.filter { !Self.displayOrder.contains($0.title) }
        return ordered.map { section in
            SearchSection(title: section.title, items: sortedItems(section))
        }
    }

    var showsAudiusResults: Bool {
        !isShowingLibrary && (selectedSectionFilter == nil || selectedSectionFilter == "Audius")
    }

    var showsQobuzResults: Bool {
        !isShowingLibrary && (selectedSectionFilter == nil || selectedSectionFilter == "Qobuz")
    }

    var showsJioSaavnResults: Bool {
        !isShowingLibrary && (selectedSectionFilter == nil || selectedSectionFilter == "JioSaavn")
    }

    var showsAddonResults: Bool {
        !isShowingLibrary && (selectedSectionFilter == nil || selectedSectionFilter == "Add-ons")
    }

    var filteredResults: [SearchSection] {
        if isShowingLibrary {
            return librarySections
        }
        guard let filter = selectedSectionFilter else { return displaySections }
        return displaySections.filter { $0.title == filter }
    }

    private var librarySections: [SearchSection] {
        var sections: [SearchSection] = []
        if !localSongs.isEmpty {
            sections.append(SearchSection(title: "Songs", items: localSongs.toSongItems().map(YTItem.song)))
        }
        if !localAlbums.isEmpty {
            sections.append(SearchSection(title: "Albums", items: localAlbums.map { YTItem.album(AlbumItem(entity: $0)) }))
        }
        if !localArtists.isEmpty {
            sections.append(SearchSection(title: "Artists", items: localArtists.map { YTItem.artist(ArtistItem(entity: $0)) }))
        }
        if !localPlaylists.isEmpty {
            sections.append(SearchSection(title: "Playlists", items: localPlaylists.map { YTItem.playlist(PlaylistItem(entity: $0)) }))
        }
        return sections
    }

    // MARK: - Sorting

    private func sortedItems(_ section: SearchSection) -> [YTItem] {
        switch section.title {
        case "Songs", "Videos":
            return sortSongs(section.items)
        case "Albums":
            // Only Date Released applies to albums (parsed release year).
            guard sort == .date else { return section.items }
            return stable(section.items) { year(of: $0) > year(of: $1) }
        default:
            return section.items
        }
    }

    private func sortSongs(_ items: [YTItem]) -> [YTItem] {
        switch sort {
        case .relevant:
            return items
        case .rating:
            // Search results expose view counts (not likes) — most-watched first.
            return stable(items) { rating(of: $0) > rating(of: $1) }
        case .date:
            return stable(items) { year(of: $0) > year(of: $1) }
        case .recent:
            return stable(items) { recency(of: $0) > recency(of: $1) }
        }
    }

    /// Stable sort: ties keep their original (relevance) order.
    private func stable(_ items: [YTItem], by areInIncreasingOrder: (YTItem, YTItem) -> Bool) -> [YTItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func rating(of item: YTItem) -> Int64 {
        switch item {
        case .song(let s): return s.viewCount ?? -1
        default: return -1
        }
    }

    private func year(of item: YTItem) -> Int {
        switch item {
        case .song(let s): return s.year ?? -1
        case .album(let a): return a.year ?? -1
        default: return -1
        }
    }

    private func recency(of item: YTItem) -> Date {
        guard let id = item.videoId, let map = recencyMap else { return .distantPast }
        return map[id] ?? .distantPast
    }

    private func preloadRecencyMap() {
        guard recencyMap == nil, !Self.recencyFetchInFlight else { return }
        Self.recencyFetchInFlight = true
        Task { [weak self] in
            defer { Self.recencyFetchInFlight = false }
            guard let entries = try? await DatabaseService.shared.fetchHistory(limit: 200) else {
                Log.search.error("Recency map failed: history fetch threw")
                return
            }
            var map: [String: Date] = [:]
            for entry in entries {
                let id = entry.event.songId
                let date = entry.event.timestamp
                if let existing = map[id] {
                    map[id] = max(existing, date)
                } else {
                    map[id] = date
                }
            }
            self?.recencyMap = map
        }
    }

    // MARK: - Submission

    /// Submits the given text (or the current field text).
    func submit(_ text: String? = nil) {
        if let text {
            fieldText = text
        }

        let query = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        Log.search.debug("Submit query='\(query)' sort=\(sort.title)")

        cancelTasks()
        submittedQuery = query
        suggestions = []
        updateHistory(query: query)
        prepareQuery()
        fetchTask = Task { [weak self] in
            await self?.fetchResults(for: query, includeProviders: true)
        }
    }

    private func prepareQuery() {
        error = nil
        selectedSectionFilter = nil
        isShowingLibrary = false
        audiusTracks = []
        qobuzTracks = []
        jiosaavnTracks = []
        addonTracks = []
        localSongs = []
        localArtists = []
        localAlbums = []
        localPlaylists = []
        results = resultCache[submittedQuery] ?? []
        extractHero()
        phase = results.isEmpty && heroArtist == nil ? .loading : .results
    }

    private func fetchResults(for query: String, includeProviders: Bool) async {
        isFetching = true
        defer { isFetching = false }
        async let localResults = try? SearchService.shared.localSearch(query: query)
        var primaryFailure: Error?
        do {
            let catalog = try await SpotifyCatalogProvider().search(query: query, limit: 30)
            guard !Task.isCancelled, query == submittedQuery else { return }
            let sections = SpotifyCatalogMapper.searchSections(from: catalog)
            resultCache[query] = sections
            cacheOrder.removeAll { $0 == query }
            cacheOrder.append(query)
            if cacheOrder.count > 20 {
                resultCache.removeValue(forKey: cacheOrder.removeFirst())
            }
            results = sections
            extractHero()
        } catch {
            guard !Task.isCancelled, query == submittedQuery else { return }
            primaryFailure = error
        }
        let local = await localResults
        guard !Task.isCancelled, query == submittedQuery else { return }
        if let local {
            localSongs = local.songs
            localArtists = local.artists
            localAlbums = local.albums
            localPlaylists = local.playlists
        }
        error = primaryFailure
        updateResultPhase()

        // Extra catalogues are fetched on submission; they never delay the
        // primary results or generate requests for every partial word.
        guard includeProviders else { return }
        async let audius = try? AudiusClient().searchTracks(query: query, limit: 25)
        async let qobuz = QobuzCatalogService.shared.searchIfConfigured(query: query, limit: 25)
        async let jiosaavn = try? JioSaavnClient().search(query: query, limit: 25)
        async let addons = fetchAddonTracks(query: query)
        let (remoteAudius, remoteQobuz, remoteJioSaavn, remoteAddons) = await (audius, qobuz, jiosaavn, addons)
        guard !Task.isCancelled, query == submittedQuery else { return }
        audiusTracks = remoteAudius ?? []
        qobuzTracks = remoteQobuz
        jiosaavnTracks = remoteJioSaavn ?? []
        addonTracks = remoteAddons
        updateResultPhase()
    }

    /// Music Add-ons (Stremio, read-only): search every enabled addon and map
    /// its items into playable catalogue tracks.
    private func fetchAddonTracks(query: String) async -> [MusicCatalogTrack] {
        let installations = Array(MusicAddonsStore.shared.enabledStremioInstallations.prefix(4))
        guard !installations.isEmpty else { return [] }

        // Every addon is queried at once; order is restored afterwards so the
        // section stays stable between searches.
        var perAddon = [[AddonTrack]](repeating: [], count: installations.count)
        await withTaskGroup(of: (Int, [AddonTrack]).self) { group in
            for (index, installation) in installations.enumerated() {
                group.addTask {
                    guard let client = try? MusicAddonClient(installation: installation),
                          let found = try? await client.search(query, limit: 10) else {
                        return (index, [])
                    }
                    return (index, found)
                }
            }
            for await (index, found) in group {
                perAddon[index] = found
            }
        }

        var tracks: [MusicCatalogTrack] = []
        for found in perAddon {
            for item in found {
                var title = item.title
                var artist = item.artist ?? ""
                if artist.isEmpty, let separator = title.range(of: " - ") {
                    artist = String(title[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
                    title = String(title[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                let storage = AddonPlaybackID.encode(key: item.installationKey, type: item.type, id: item.id)
                let raw = String(storage.dropFirst(AddonPlaybackID.prefix.count))
                tracks.append(MusicCatalogTrack(
                    id: MusicCatalogID(source: .addon, rawValue: raw),
                    title: title.isEmpty ? item.title : title,
                    artist: artist,
                    durationSeconds: item.durationSeconds ?? 0,
                    artworkURL: item.poster,
                    permalinkURL: nil,
                    isStreamable: true
                ))
            }
        }
        return tracks
    }

    private func updateResultPhase() {
        if results.isEmpty && heroArtist == nil && audiusTracks.isEmpty && qobuzTracks.isEmpty && jiosaavnTracks.isEmpty && addonTracks.isEmpty {
            phase = error == nil ? .noResults : .failed
        } else {
            phase = .results
        }
    }

    /// Artist-first layout: when the top result is an artist, lift it (plus
    /// its top songs from the same card) into the hero and remove them from
    /// the flat sections so nothing shows twice.
    private func extractHero() {
        heroArtist = nil
        heroSongs = []
        guard let index = results.firstIndex(where: { section in
            if case .artist = section.items.first { return true }
            return false
        }) else { return }
        guard case .artist(let artist) = results[index].items.first else { return }
        heroArtist = artist
        heroSongs = results[index].items.dropFirst().compactMap { item in
            if case .song(let song) = item { return song }
            return nil
        }
        let remaining = results[index].items.filter { item in
            if case .artist = item { return false }
            if case .song(let song) = item { return !heroSongs.contains(where: { $0.videoId == song.videoId }) }
            return true
        }
        if remaining.isEmpty {
            results.remove(at: index)
        } else {
            results[index].items = remaining
        }
    }

    // MARK: - Field changes

    /// Cancel the current search and return to recent searches.
    func closeSearch() {
        fieldText = ""
        resetToIdle()
    }

    private func handleFieldTextChange() {
        cancelTasks()
        let query = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            resetToIdle()
            return
        }
        submittedQuery = query
        suggestions = suggestionCache[query] ?? []
        prepareQuery()
        suggestionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard let self, !Task.isCancelled else { return }
                let values: [String]
                if let cached = self.suggestionCache[query] {
                    values = cached
                } else {
                    values = Array(try await SearchSuggestions.suggest(query: query).prefix(5))
                }
                guard !Task.isCancelled, self.submittedQuery == query else { return }
                // Dedupe (case-insensitive) so `ForEach(id: \.self)` never hits
                // duplicate identities.
                var seen = Set<String>()
                let unique = values.filter { seen.insert($0.lowercased()).inserted }
                if self.suggestionCache.count >= 40 { self.suggestionCache.removeAll() }
                self.suggestionCache[query] = unique
                self.suggestions = unique
            } catch { /* Suggestions are optional; results continue independently. */ }
        }
        fetchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await self?.fetchResults(for: query, includeProviders: false)
        }
    }

    /// Clears any shown results and returns to the recent-searches state.
    private func resetToIdle() {
        cancelTasks()
        submittedQuery = ""
        suggestions = []
        results = []
        audiusTracks = []
        qobuzTracks = []
        jiosaavnTracks = []
        addonTracks = []
        localSongs = []
        localArtists = []
        localAlbums = []
        localPlaylists = []
        selectedSectionFilter = nil
        isShowingLibrary = false
        heroArtist = nil
        heroSongs = []
        error = nil
        phase = .idle
    }

    // MARK: - History

    func loadSearchHistory() {
        var queries = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []

        if !UserDefaults.standard.bool(forKey: Self.historyNewestFirstKey) {
            queries.reverse()
            UserDefaults.standard.set(queries, forKey: Self.historyKey)
            UserDefaults.standard.set(true, forKey: Self.historyNewestFirstKey)
        }

        searchHistory = queries.map { SearchHistoryEntity(query: $0, timestamp: Date()) }
    }

    func clearSearchHistory() {
        searchHistory = []
        saveHistory()
    }

    func deleteSearchHistoryEntry(_ entry: SearchHistoryEntity) {
        searchHistory.removeAll { $0.query == entry.query }
        saveHistory()
    }

    private func updateHistory(query: String) {
        guard SettingsStore.shared.trackSearchHistory else { return }

        var queries = searchHistory.map(\.query)
        if let index = queries.firstIndex(of: query) {
            queries.remove(at: index)
        }
        queries.insert(query, at: 0)

        if queries.count > Self.maxHistoryEntries {
            queries.removeLast()
        }

        UserDefaults.standard.set(queries, forKey: Self.historyKey)
        UserDefaults.standard.set(true, forKey: Self.historyNewestFirstKey)
        searchHistory = queries.map { SearchHistoryEntity(query: $0, timestamp: Date()) }
    }

    private func saveHistory() {
        UserDefaults.standard.set(searchHistory.map(\.query), forKey: Self.historyKey)
    }

    // MARK: - Private helpers

    private func cancelTasks() {
        fetchTask?.cancel()
        suggestionTask?.cancel()
    }

}
