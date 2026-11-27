//
//  HomeScreenView.swift
//  Apollo
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct HomeScreenView: View {
    @Environment(SettingsStore.self) private var settings
    @ObservedObject private var router = AppRouter.shared
    @State private var viewModel = HomeViewModel()
    private let accountState = AccountSheetState.shared

    @State private var pendingRoute: DetailRoute?
    @State private var headerOffset: CGFloat = 0

    /// Coalesces scroll-offset writes into ~8pt steps so the whole feed isn't
    /// re-evaluated on every scroll frame (0→1→2…). The header/mini-player
    /// animation resolves the small steps.
    private var quantizedHeaderOffset: Binding<CGFloat> {
        Binding(
            get: { headerOffset },
            set: { newValue in
                if abs(newValue - headerOffset) >= 8 { headerOffset = newValue }
            }
        )
    }
    @State private var headerHeight: CGFloat = 60
    @State private var speedDialEntries: [SpeedDialEntry] = []
    @State private var selectedCategory: ContentCategory = .all
    @State private var forYouSongs: [SongItem] = []
    @State private var discoverArtists: [ArtistItem] = []
    @State private var podcastSuggestions: [YTItem] = []

    var body: some View {
        NavigationStack(path: $router.homePath) {
            ZStack(alignment: .top) {
                Group {
                    if viewModel.isLoading {
                        ShimmerLoadingView()
                    } else if let error = viewModel.error {
                        errorView(error)
                    } else {
                        homescreenContent
                    }
                }
                TabHeaderView(
                    title: "Home",
                    accountIsLoggedIn: accountState.isLoggedIn,
                    accountImageUrl: accountState.accountImageUrl,
                    onAccount: { router.homePath.append(DetailRoute.settings) },
                    accountInitial: accountState.accountName.first.map(String.init)
                )
                .floatingTabHeader(scrollOffset: headerOffset, height: $headerHeight)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .detailRouteDestinations()
            .onChange(of: pendingRoute) { _, route in
                if let route {
                    router.homePath.append(route)
                    pendingRoute = nil
                }
            }
            .onChange(of: accountState.isLoggedIn) { _, loggedIn in
                viewModel.handleSessionChange(loggedIn: loggedIn)
            }
            .task {
                await viewModel.restoreSession()
                await accountState.restoreSession()
                await accountState.fetchAccountInfo()
                viewModel.loadHomeData()
                await reloadSpeedDial()
                // Trigger library sync in background
                Task {
                    await SyncBridge.checkAndSyncIfStale()
                }
            }
            .task(id: viewModel.homeSections.count) {
                let urls = viewModel.homeSections
                    .flatMap(\.items)
                    .compactMap(\.thumbnailUrl)
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
        }
    }

    private var homescreenContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: headerHeight)
                categoryChips
                surpriseCard

                ForEach(visibleSections) { section in
                    sectionView(for: section)
                }

                if visibleSections.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        LocalizedStringKey(emptyCategoryTitle),
                        systemImage: emptyCategorySymbol,
                        description: Text("Pull to refresh or try another category.")
                    )
                    .padding(.top, 50)
                }

                GeometryReader { _ in
                    Color.clear
                        .onAppear {
                            let total = viewModel.homeSections.count
                            if total > 0 {
                                viewModel.loadMoreIfNeeded(
                                    currentIndex: total - 1,
                                    total: total
                                )
                            }
                        }
                }
                .frame(height: 1)
            }
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll(headerOffset: quantizedHeaderOffset).scrollEdgeEffectHidden(true, for: .bottom)
        .task(id: selectedCategory) {
            await viewModel.loadCategoryFeed(selectedCategory)
        }
        .task {
            async let songsTask = DiscoveryService.songs()
            async let artistsTask = DiscoveryService.artists()
            async let podcastsTask = DiscoveryService.podcasts()
            forYouSongs = await songsTask
            discoverArtists = await artistsTask
            podcastSuggestions = await podcastsTask
        }
        .refreshable {
            await viewModel.refresh()
            await reloadSpeedDial()
            await SyncBridge.checkAndSyncIfStale()
        }
        .onChange(of: settings.hideExplicit) { _, _ in
            viewModel.syncSettings()
        }
        .onChange(of: settings.showQuickPicks) { _, _ in
            viewModel.syncSettings()
            Task { await viewModel.refresh() }
        }
        .onChange(of: settings.topListsLength) { _, _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: settings.contentCountry) { _, _ in
            Task { await viewModel.refresh() }
        }
    }

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section {
        case .quickPicks:
            songRowsSection(section, includesPinned: true)
        case .keepListening:
            mixedSection(section)
        case .forgottenFavorites:
            songsSection(section)
        case .homePageSection(let sectionData, _):
            if sectionData.isSongsOnly {
                songsSection(section)
            } else {
                mixedSection(section)
            }
        default:
            mixedSection(section)
        }
    }

    @ViewBuilder
    private func songRowsSection(_ section: HomeSection, includesPinned: Bool = false) -> some View {
        let pinnedEntries = includesPinned ? speedDialEntries : []
        let pinnedSongs = pinnedEntries.map { $0.toSongItem() }
        let pinnedIds = Set(pinnedEntries.map(\.videoId))
        let visibleItems = section.items.filter { item in
            if case .song(let s) = item { return !pinnedIds.contains(s.videoId) }
            return true
        }
        let quickSongs = visibleItems.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        let combinedQueue = pinnedSongs + quickSongs

        return Group {
            if combinedQueue.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(LocalizedStringKey(section.displayTitle))
                            .font(.title2.bold())
                        Spacer()
                        Button {
                            PlaybackQueue.play(combinedQueue, log: Log.homeScreenView, context: "Quick picks play all")
                        } label: {
                            Text("Play all")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.quaternary))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    GeometryReader { geometry in
                        let columnWidth = max(1, geometry.size.width - 48)
                        ScrollView(.horizontal) {
                            LazyHGrid(
                                rows: Array(repeating: GridItem(.fixed(56), spacing: 16), count: 4),
                                spacing: 16
                            ) {
                                ForEach(pinnedEntries, id: \.videoId) { entry in
                                    let song = entry.toSongItem()
                                    quickPickCell(song, queue: combinedQueue)
                                        .frame(width: columnWidth)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: "pin.fill")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(settings.accentColor)
                                                .padding(4)
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                Task {
                                                    try? await DatabaseService.shared.removeFromSpeedDial(videoId: entry.videoId)
                                                    await reloadSpeedDial()
                                                }
                                            } label: {
                                                Label("Unpin", systemImage: "pin.slash")
                                            }
                                        }
                                }

                                ForEach(visibleItems, id: \.id) { item in
                                    if case .song(let s) = item {
                                        quickPickCell(s, queue: combinedQueue)
                                            .frame(width: columnWidth)
                                    } else {
                                        YouTubeListItemView(
                                            item: item,
                                            onTap: { handleItemTap(item) },
                                            onNavigate: { pendingRoute = $0 }
                                        )
                                        .frame(width: columnWidth, height: 56)
                                    }
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .contentMargins(.horizontal, 16, for: .scrollContent)
                        .scrollTargetBehavior(.viewAligned)
                        .scrollIndicators(.hidden)
                    }
                    .frame(height: 4 * 56 + 3 * 16)
                }
            }
        }
    }

    private func quickPickSubtitle(_ song: SongItem) -> String {
        var parts: [String] = []
        let artist = song.artistNamesDisplay
        if !artist.isEmpty { parts.append(artist) }
        if let views = song.viewCount, views > 0 {
            parts.append("\(compactCount(views)) plays")
        } else if song.duration > 0 {
            parts.append(song.duration.formattedDuration)
        }
        return parts.joined(separator: " · ")
    }

    private func compactCount(_ value: Int64) -> String {
        let v = Double(value)
        func trim(_ s: String) -> String { s.replacingOccurrences(of: ".0", with: "") }
        if v >= 1_000_000_000 { return trim(String(format: "%.1fB", v / 1_000_000_000)) }
        if v >= 1_000_000 { return trim(String(format: "%.1fM", v / 1_000_000)) }
        if v >= 1_000 { return trim(String(format: "%.1fK", v / 1_000)) }
        return "\(value)"
    }

    private func quickPickCell(_ song: SongItem, queue: [SongItem]) -> some View {
        let metadata = NowPlaying.shared.metadataSnapshot(for: song.videoId)
        return HStack(spacing: 16) {
            SongArtworkView(song: song)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(metadata?.title ?? song.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(metadata?.artist ?? quickPickSubtitle(song))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            Spacer(minLength: 0)

            Menu {
                SongContextMenuButtons(song: song)
            } label: {
                Text("⋮")
                    .font(.body.weight(.black))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 56)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
        }
        .contentShape(Rectangle())
        .onTapGesture { handleSongTap(song, in: queue) }
        .contextMenu { SongContextMenuButtons(song: song) }
    }

    private func songsSection(_ section: HomeSection) -> some View {
        songRowsSection(section)
    }

    private func mixedSection(_ section: HomeSection) -> some View {
        let queue = section.items.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        return HorizontalSection(title: section.displayTitle, vSpacing: 8, contentVerticalPadding: 0) {
            // Lazy so off-screen cards (and their image loads) build on approach.
            LazyHStack(spacing: 12) {
                ForEach(section.items, id: \.id) { item in
                    if case .song(let s) = item, !queue.isEmpty {
                        YouTubeGridItemView(item: item, onTap: { handleSongTap(s, in: queue) })
                    } else {
                        YouTubeGridItemView(item: item, onTap: { handleItemTap(item) })
                    }
                }
            }
        }.padding(.top, 8)
    }

    // MARK: - Quick Picks (pinned)

    private func reloadSpeedDial() async {
        speedDialEntries = (try? await DatabaseService.shared.fetchSpeedDial()) ?? []
    }

    private func handleSongTap(_ song: SongItem, in queue: [SongItem]) {
        Log.homeScreenView.debug("Tapped song in queue: \(song.title) queueCount=\(queue.count)")
        PlaybackQueue.play(song, in: queue, log: Log.homeScreenView, context: "Tapped song")
    }

    /// Sections for the active Home filter. "All" mixes everything but is
    /// capped so the feed doesn't feel overloaded.
    private var visibleSections: [HomeSection] {
        switch selectedCategory {
        case .all:
            // Decluttered: only Quick Picks and Keep Listening; everything else
            // is AI discovery (songs, new artists, podcasts) right after Quick Picks.
            let quick = viewModel.homeSections.filter { if case .quickPicks = $0 { return true }; return false }
            let keep = viewModel.homeSections.filter { if case .keepListening = $0 { return true }; return false }
            var sections = quick + keep
            sections.insert(contentsOf: aiSections(music: true, podcasts: true), at: min(1, sections.count))
            return sections
        case .music:
            var sections = viewModel.homeSections.filter { $0.category == .music }
            sections.insert(contentsOf: aiSections(music: true, podcasts: false), at: 0)
            return sections
        case .podcast, .audiobook:
            // Each of these is its own feed; fall back to matching home sections.
            var sections = (viewModel.categoryFeeds[selectedCategory] ?? [])
                .enumerated()
                .map { HomeSection.homePageSection($0.element, index: $0.offset) }
            if sections.isEmpty {
                sections = viewModel.homeSections.filter { $0.category == selectedCategory }
            }
            if selectedCategory == .podcast {
                sections.insert(contentsOf: aiSections(music: false, podcasts: true), at: 0)
            }
            return sections
        }
    }

    /// AI discovery shelves: songs, new artists and podcasts.
    private func aiSections(music: Bool, podcasts: Bool) -> [HomeSection] {
        var result: [HomeSection] = []
        if music, !forYouSongs.isEmpty {
            result.append(.similarRecommendation(items: forYouSongs.map(YTItem.song), title: "For You"))
        }
        if music, !discoverArtists.isEmpty {
            result.append(.similarRecommendation(items: discoverArtists.map(YTItem.artist), title: "Artists for you"))
        }
        if podcasts, !podcastSuggestions.isEmpty {
            result.append(.similarRecommendation(items: podcastSuggestions, title: "Podcasts for you"))
        }
        return result
    }

    private var surpriseCard: some View {
        Button {
            handleSurprise()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shuffle")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(settings.accentColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Surprise Me")
                        .font(.headline)
                    Text(LocalizedStringKey(surpriseSubtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var surpriseSubtitle: String {
        switch selectedCategory {
        case .all, .music: return "Not sure what to play? Discover a song."
        case .podcast: return "Not sure what to play? Discover a podcast."
        case .audiobook: return "Not sure what to play? Discover an audiobook."
        }
    }

    private func handleSurprise() {
        switch selectedCategory {
        case .all, .music:
            // "All" surprises with music only, as requested. Starts a longer
            // AI-assisted queue; the AI keeps refilling it as it plays.
            Task {
                let items = await SurpriseMeService.musicQueue(seedVideoId: NowPlaying.shared.videoId)
                guard !items.isEmpty, let start = items.indices.randomElement() else { return }
                PlaybackQueue.play(items, startIndex: start, log: Log.homeScreenView, context: "Surprise music")
                NowPlaying.shared.isSurpriseSession = true
            }
        case .podcast:
            let episodes = SurpriseMeService.episodes(from: visibleSections)
            if let start = episodes.indices.randomElement() {
                PlaybackQueue.play(episodes, startIndex: start, log: Log.homeScreenView, context: "Surprise podcast")
            }
        case .audiobook:
            if let book = SurpriseMeService.audiobook(from: visibleSections) {
                router.homePath.append(DetailRoute.album(browseId: book.browseId))
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ContentCategory.allCases) { category in
                    let isOn = selectedCategory == category
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(LocalizedStringKey(category.title))
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                isOn ? settings.accentColor : Color(uiColor: .secondarySystemBackground),
                                in: Capsule()
                            )
                            .foregroundStyle(isOn ? settings.accentColor.readableForeground : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var emptyCategoryTitle: String {
        switch selectedCategory {
        case .all: return "Nothing here yet"
        case .music: return "No music"
        case .podcast: return "No podcasts"
        case .audiobook: return "No audiobooks"
        }
    }

    private var emptyCategorySymbol: String {
        switch selectedCategory {
        case .podcast: return "mic"
        case .audiobook: return "book.closed"
        default: return "music.note"
        }
    }

    private func handleItemTap(_ item: YTItem) {
        Log.homeScreenView.debug("Tapped item: \(item.title) type=\(typeName(item))")
        YTItemRouter.route(
            item,
            playSong: { PlaybackQueue.playSingleWithRadio($0, log: Log.homeScreenView) },
            appendRoute: { router.homePath.append($0) }
        )
    }

    private func typeName(_ item: YTItem) -> String {
        switch item {
        case .song: return "song"
        case .album: return "album"
        case .artist: return "artist"
        case .playlist: return "playlist"
        case .podcast: return "podcast"
        case .episode: return "episode"
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView(
            "Couldn't load your homescreen",
            systemImage: "wifi.slash",
            description: Text(error.localizedDescription)
        )
    }
}

#Preview {
    HomeScreenView()
}
