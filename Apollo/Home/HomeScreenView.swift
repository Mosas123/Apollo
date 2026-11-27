//
//  HomeScreenView.swift
//  Apollo
//
//  The Apollo Home: a living sky, one editorial hero, and a simple orbit
//  between music, podcasts and audiobooks.
//

import Foundation
import SwiftUI

struct HomeScreenView: View {
    @Environment(SettingsStore.self) private var settings
    @ObservedObject private var router = AppRouter.shared
    @State private var viewModel = HomeViewModel()
    private let accountState = AccountSheetState.shared

    @State private var pendingRoute: DetailRoute?
    @State private var headerOffset: CGFloat = 0
    @State private var speedDialEntries: [SpeedDialEntry] = []
    @State private var selectedCategory: ContentCategory = .all
    @State private var forYouSongs: [SongItem] = []
    @State private var discoverArtists: [ArtistItem] = []
    @State private var podcastSuggestions: [YTItem] = []

    private struct QuickTileModel: Identifiable {
        let item: YTItem
        let isPinned: Bool
        var id: String { item.id }
    }

    private struct HeroModel {
        let item: YTItem
        let label: String
        let subtitle: String
        let progress: Double?
    }

    private var accent: Color {
        selectedCategory == .all ? settings.accentColor : selectedCategory.homeAccent
    }

    /// Coalesces scroll-offset writes into ~8pt steps so the whole feed isn't
    /// re-evaluated on every scroll frame.
    private var quantizedHeaderOffset: Binding<CGFloat> {
        Binding(
            get: { headerOffset },
            set: { newValue in
                if abs(newValue - headerOffset) >= 8 { headerOffset = newValue }
            }
        )
    }

    var body: some View {
        NavigationStack(path: $router.homePath) {
            ZStack(alignment: .top) {
                HomeSkyBackground(accent: accent)
                    .ignoresSafeArea()

                Group {
                    if viewModel.isLoading {
                        loadingContent
                    } else if let error = viewModel.error {
                        errorView(error)
                    } else {
                        homescreenContent
                    }
                }

                compactBar
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
                Task {
                    await SyncBridge.checkAndSyncIfStale()
                }
            }
        }
    }

    // MARK: - Content

    private var homescreenContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HomeGreetingHeader(
                        greeting: greeting,
                        dateLine: dateLine,
                        accent: accent,
                        accountIsLoggedIn: accountState.isLoggedIn,
                        accountImageUrl: accountState.accountImageUrl,
                        accountInitial: accountState.accountName.first.map(String.init),
                        onAccount: { router.homePath.append(DetailRoute.settings) }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .id("homeTop")

                    if let hero {
                        HomeHeroCard(
                            item: hero.item,
                            label: hero.label,
                            subtitle: hero.subtitle,
                            accent: accent,
                            progress: hero.progress,
                            onTap: { handleItemTap(hero.item) }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.94, anchor: .top)
                                .opacity(phase.isIdentity ? 1 : 0.55)
                        }
                    }

                    HomeOrbitSelector(selection: $selectedCategory, accent: accent)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)

                    if isEmptyFeed {
                        emptyState
                            .padding(.top, 44)
                    } else {
                        if !continueItems.isEmpty {
                            continueSection.padding(.top, 30)
                        }

                        if !quickModels.isEmpty {
                            quickPicksSection.padding(.top, 30)
                        }

                        ForEach(restSections) { section in
                            shelfSection(section).padding(.top, 30)
                        }

                        surpriseBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 34)
                    }

                    Color.clear.frame(height: 40)
                }
            }
            .scrollIndicators(.hidden)
            .miniPlayerTracksScroll(headerOffset: quantizedHeaderOffset)
            .scrollEdgeEffectHidden(true, for: .bottom)
            .refreshable {
                await viewModel.refresh()
                await reloadSpeedDial()
                await SyncBridge.checkAndSyncIfStale()
            }
            .onChange(of: selectedCategory) { _, _ in
                withAnimation(.smooth(duration: 0.4)) {
                    proxy.scrollTo("homeTop", anchor: .top)
                }
            }
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
            .task(id: viewModel.homeSections.count) {
                guard !viewModel.homeSections.isEmpty else { return }
                // Podcast and audiobook feeds make the unified orbit complete.
                await viewModel.loadCategoryFeed(.podcast)
                await viewModel.loadCategoryFeed(.audiobook)
                await preloadArtwork()
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
    }

    private var loadingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    ShimmerFill(radius: 4).frame(width: 66, height: 11)
                    ShimmerFill(radius: 9).frame(width: 236, height: 36)
                    ShimmerFill(radius: 4).frame(width: 152, height: 13)
                }

                ShimmerFill(radius: 30).frame(height: 380)

                ShimmerFill(radius: 22).frame(height: 64)

                HStack(spacing: 12) {
                    ShimmerFill(radius: 22).frame(width: 300, height: 92)
                    ShimmerFill(radius: 22).frame(width: 300, height: 92)
                }

                ShimmerFill(radius: 22).frame(height: 178)
                ShimmerFill(radius: 22).frame(height: 178)
            }
            .padding(20)
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView(
            "The sky is quiet",
            systemImage: "cloud.slash",
            description: Text(error.localizedDescription)
        )
        .padding(.top, 80)
    }

    private var compactBar: some View {
        let opacity = min(max((headerOffset - 36) / 70, 0), 1)
        return HStack(spacing: 9) {
            Text("A")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(accent, in: Circle())

            Text("Apollo")
                .font(.headline.weight(.bold))

            Spacer(minLength: 12)

            AccountButtonView(
                isLoggedIn: accountState.isLoggedIn,
                accountImageUrl: accountState.accountImageUrl,
                size: 30,
                initial: accountState.accountName.first.map(String.init),
                onTap: { router.homePath.append(DetailRoute.settings) }
            )
            .accessibilityLabel("Account")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .opacity(opacity)
        .allowsHitTesting(opacity > 0.2)
        .animation(.easeInOut(duration: 0.18), value: opacity)
    }

    // MARK: - Hero

    private var hero: HeroModel? {
        let item: YTItem?
        switch selectedCategory {
        case .podcast:
            item = firstItem(in: restSections) { item in
                if case .episode = item { return true }
                if case .podcast = item { return true }
                return false
            }
        case .audiobook:
            item = firstItem(in: restSections) { item in
                if case .album(let album) = item { return album.isAudiobook }
                return false
            }
        case .all, .music:
            if let current = currentFeedItem {
                item = current
            } else if let keep = continueItems.first {
                item = keep
            } else if let song = forYouSongs.first {
                item = .song(song)
            } else {
                item = quickModels.first?.item
            }
        }

        guard let item else { return nil }

        let isNowPlaying = item.videoId != nil && item.videoId == NowPlaying.shared.videoId
        let label: String
        if isNowPlaying {
            label = "Now playing"
        } else if selectedCategory == .podcast {
            label = "Up next"
        } else if selectedCategory == .audiobook {
            label = "Continue the book"
        } else if continueItems.contains(where: { $0.id == item.id }) {
            label = "Pick up"
        } else {
            label = "Made for you"
        }

        return HeroModel(
            item: item,
            label: label,
            subtitle: item.homeSubtitle,
            progress: isNowPlaying ? Double(NowPlaying.shared.progress) : nil
        )
    }

    private var currentFeedItem: YTItem? {
        guard let currentId = NowPlaying.shared.videoId else { return nil }
        let pool = continueItems + quickModels.map(\.item) + forYouSongs.map(YTItem.song)
        return pool.first { $0.videoId == currentId }
    }

    // MARK: - Continue

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(
                kicker: selectedCategory.homeKicker,
                title: "Pick up where you left off",
                accent: accent
            )
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(continueItems, id: \.id) { item in
                        HomeContinueCard(item: item, accent: accent) {
                            handleItemTap(item)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Quick picks

    private var quickPicksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 12) {
                HomeSectionHeader(kicker: "Curated", title: "Quick picks", accent: accent)
                Spacer(minLength: 0)
                if !quickQueue.isEmpty {
                    Button {
                        PlaybackQueue.play(
                            quickQueue,
                            log: Log.homeScreenView,
                            context: "Quick picks play all"
                        )
                    } label: {
                        Text("Play all")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ],
                spacing: 20
            ) {
                ForEach(quickModels) { model in
                    HomeQuickTile(
                        item: model.item,
                        isPinned: model.isPinned,
                        accent: accent
                    ) {
                        tapQuick(model)
                    }
                    .contextMenu {
                        if model.isPinned {
                            unpinButton(model)
                        } else {
                            YTItemContextMenu(item: model.item)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Shelves

    private func shelfSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(
                kicker: sectionKicker(for: section),
                title: section.displayTitle,
                accent: sectionAccent(for: section)
            )
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(section.items.prefix(12), id: \.id) { item in
                        HomeShelfCard(item: item, accent: sectionAccent(for: section)) {
                            handleItemTap(item)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
    }

    private var surpriseBanner: some View {
        HomeSurpriseBanner(
            accent: accent,
            title: surpriseTitle,
            subtitle: surpriseSubtitle
        ) {
            handleSurprise()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            emptyCategoryTitle,
            systemImage: selectedCategory.homeSymbol,
            description: Text("Pull to refresh or try another orbit.")
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Feed data

    private var keepSection: HomeSection? {
        viewModel.homeSections.first { section in
            if case .keepListening = section { return true }
            return false
        }
    }

    private var quickSection: HomeSection? {
        viewModel.homeSections.first { section in
            if case .quickPicks = section { return true }
            return false
        }
    }

    private var continueItems: [YTItem] {
        Array((keepSection?.items ?? []).prefix(10))
    }

    private var quickModels: [QuickTileModel] {
        let pinned = speedDialEntries.map {
            QuickTileModel(item: .song($0.toSongItem()), isPinned: true)
        }
        let pinnedIds = Set(pinned.compactMap { $0.item.videoId })

        let others = (quickSection?.items ?? []).filter { item in
            guard let videoId = item.videoId else { return true }
            return !pinnedIds.contains(videoId)
        }.map { QuickTileModel(item: $0, isPinned: false) }

        return Array((pinned + others).prefix(8))
    }

    private var quickQueue: [SongItem] {
        let pinned = speedDialEntries.map { $0.toSongItem() }
        let pinnedIds = Set(pinned.map(\.videoId))
        let songs = (quickSection?.items ?? []).compactMap { item -> SongItem? in
            guard case .song(let song) = item, !pinnedIds.contains(song.videoId) else { return nil }
            return song
        }
        return pinned + songs
    }

    private var restSections: [HomeSection] {
        let base = viewModel.homeSections.filter { section in
            switch section {
            case .quickPicks, .keepListening:
                return false
            default:
                return !section.items.isEmpty
            }
        }

        var result: [HomeSection] = []
        switch selectedCategory {
        case .music:
            result += aiSections(music: true, podcasts: false)
            result += base.filter { $0.category == .music }
        case .podcast:
            result += aiSections(music: false, podcasts: true)
            result += categorySections(.podcast, offset: 100)
            result += base.filter { $0.category == .podcast }
        case .audiobook:
            result += categorySections(.audiobook, offset: 200)
            result += base.filter { $0.category == .audiobook }
        case .all:
            result += aiSections(music: true, podcasts: true)
            result += Array(base.filter { $0.category == .music }.prefix(4))
            result += Array(base.filter { $0.category == .podcast }.prefix(2))
            result += Array(base.filter { $0.category == .audiobook }.prefix(2))
            result += Array(categorySections(.podcast, offset: 100).prefix(1))
            result += Array(categorySections(.audiobook, offset: 200).prefix(1))
        }

        var seen = Set<String>()
        return Array(result.filter { seen.insert($0.id).inserted }.prefix(12))
    }

    private var isEmptyFeed: Bool {
        hero == nil
            && continueItems.isEmpty
            && quickModels.isEmpty
            && restSections.isEmpty
    }

    private func categorySections(_ category: ContentCategory, offset: Int) -> [HomeSection] {
        (viewModel.categoryFeeds[category] ?? [])
            .enumerated()
            .map { HomeSection.homePageSection($0.element, index: $0.offset + offset) }
            .filter { !$0.items.isEmpty }
    }

    private func firstItem(
        in sections: [HomeSection],
        where predicate: (YTItem) -> Bool
    ) -> YTItem? {
        for section in sections {
            if let item = section.items.first(where: predicate) { return item }
        }
        return nil
    }

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

    // MARK: - Copy & accents

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<23: return "Good evening"
        default: return "Late night"
        }
    }

    private var dateLine: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var surpriseTitle: String {
        switch selectedCategory {
        case .all, .music: return "Let the sky decide"
        case .podcast: return "Find your next listen"
        case .audiobook: return "Open a new world"
        }
    }

    private var surpriseSubtitle: String {
        switch selectedCategory {
        case .all, .music: return "A fresh song, chosen for right now."
        case .podcast: return "A new episode from somewhere unexpected."
        case .audiobook: return "A book you haven't met yet."
        }
    }

    private var emptyCategoryTitle: String {
        switch selectedCategory {
        case .all: return "Nothing in your orbit yet"
        case .music: return "No music yet"
        case .podcast: return "No podcasts yet"
        case .audiobook: return "No audiobooks yet"
        }
    }

    private func sectionKicker(for section: HomeSection) -> String {
        if case .similarRecommendation(_, let title) = section {
            switch title {
            case "For You": return "Made for you"
            case "Artists for you": return "Artists"
            case "Podcasts for you": return "Podcasts"
            default: return "For you"
            }
        }
        return section.category.homeKicker
    }

    private func sectionAccent(for section: HomeSection) -> Color {
        section.category == .all ? accent : section.category.homeAccent
    }

    private var surpriseSections: [HomeSection] {
        var sections = viewModel.homeSections + restSections
        if let quickSection { sections.append(quickSection) }
        if let keepSection { sections.append(keepSection) }
        return sections
    }

    // MARK: - Actions

    private func reloadSpeedDial() async {
        speedDialEntries = (try? await DatabaseService.shared.fetchSpeedDial()) ?? []
    }

    private func preloadArtwork() async {
        var urls = viewModel.homeSections
            .flatMap(\.items)
            .compactMap(\.thumbnailUrl)
            .compactMap(URL.init)

        for category in [ContentCategory.podcast, .audiobook] {
            urls += (viewModel.categoryFeeds[category] ?? [])
                .flatMap(\.items)
                .compactMap(\.thumbnailUrl)
                .compactMap(URL.init)
        }

        await ImagePreloader.shared.preload(urls)
    }

    private func tapQuick(_ model: QuickTileModel) {
        if case .song(let song) = model.item {
            handleSongTap(song, in: quickQueue)
        } else {
            handleItemTap(model.item)
        }
    }

    @ViewBuilder
    private func unpinButton(_ model: QuickTileModel) -> some View {
        Button(role: .destructive) {
            guard let videoId = model.item.videoId else { return }
            Task {
                try? await DatabaseService.shared.removeFromSpeedDial(videoId: videoId)
                await reloadSpeedDial()
            }
        } label: {
            Label("Unpin", systemImage: "pin.slash")
        }
    }

    private func handleSongTap(_ song: SongItem, in queue: [SongItem]) {
        Log.homeScreenView.debug("Tapped song in queue: \(song.title) queueCount=\(queue.count)")
        PlaybackQueue.play(song, in: queue, log: Log.homeScreenView, context: "Tapped song")
    }

    private func handleItemTap(_ item: YTItem) {
        Log.homeScreenView.debug("Tapped item: \(item.title) kind=\(item.homeKindLabel)")
        YTItemRouter.route(
            item,
            playSong: { PlaybackQueue.playSingleWithRadio($0, log: Log.homeScreenView) },
            appendRoute: { router.homePath.append($0) }
        )
    }

    private func handleSurprise() {
        switch selectedCategory {
        case .all, .music:
            Task {
                let items = await SurpriseMeService.musicQueue(seedVideoId: NowPlaying.shared.videoId)
                guard !items.isEmpty, let start = items.indices.randomElement() else { return }
                PlaybackQueue.play(items, startIndex: start, log: Log.homeScreenView, context: "Surprise music")
                NowPlaying.shared.isSurpriseSession = true
            }
        case .podcast:
            let episodes = SurpriseMeService.episodes(from: surpriseSections)
            if let start = episodes.indices.randomElement() {
                PlaybackQueue.play(episodes, startIndex: start, log: Log.homeScreenView, context: "Surprise podcast")
            }
        case .audiobook:
            if let book = SurpriseMeService.audiobook(from: surpriseSections) {
                router.homePath.append(DetailRoute.album(browseId: book.browseId))
            }
        }
    }
}

#Preview {
    HomeScreenView()
}
