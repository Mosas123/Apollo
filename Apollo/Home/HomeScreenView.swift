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
    @State private var episodeCovers: [String: String] = [:]
    @State private var fetchedShowIds: Set<String> = []

    private struct QuickTileModel: Identifiable {
        let item: YTItem
        let isPinned: Bool
        var id: String { item.id }
    }

    private struct HeroModel {
        let display: HomeHeroDisplay
        let label: String
        let progress: Double?
        let isNowPlaying: Bool
        let item: YTItem?
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
            .environment(\.podcastCovers, podcastCoverMap)
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
                            display: hero.display,
                            label: hero.label,
                            accent: accent,
                            progress: hero.progress
                        ) {
                            if hero.isNowPlaying {
                                openPlayer()
                            } else if let item = hero.item {
                                handleItemTap(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.94, anchor: .top)
                                .opacity(phase.isIdentity ? 1 : 0.55)
                        }
                    }

                    HomeOrbitSelector(selection: $selectedCategory, accent: accent)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    if isEmptyFeed {
                        emptyState
                            .padding(.top, 44)
                    } else {
                        if !continueItems.isEmpty {
                            continueSection.padding(.top, 24)
                        }

                        if !quickModels.isEmpty {
                            quickPicksSection.padding(.top, 24)
                        }

                        ForEach(restSections) { section in
                            shelfSection(section).padding(.top, 24)
                        }

                        surpriseBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
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
            .task(id: podcastShows.count) {
                await loadPodcastEpisodeCovers()
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

                ShimmerFill(radius: 30).frame(height: 300)

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
        return VStack(spacing: 0) {
            HStack(spacing: 9) {
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
            .padding(.top, 5)
            .padding(.bottom, 5)
        }
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
        .opacity(opacity)
        .allowsHitTesting(opacity > 0.2)
        .animation(.easeInOut(duration: 0.18), value: opacity)
    }

    // MARK: - Hero

    private var hero: HeroModel? {
        if let nowPlayingHero, shouldShowNowPlayingHero { return nowPlayingHero }

        let item: YTItem?
        switch selectedCategory {
        case .podcast:
            let covered = podcastEpisodes.first {
                podcastCoverURL(for: $0, in: podcastCoverMap) != nil
            }
            item = covered ?? podcastShows.first ?? podcastEpisodes.first
        case .audiobook:
            item = audiobooks.first
        case .all, .music:
            if let keep = continueItems.first {
                item = keep
            } else if let song = forYouSongs.first {
                item = .song(song)
            } else {
                item = quickModels.first?.item
            }
        }

        guard let item else { return nil }

        let label: String
        if selectedCategory == .podcast {
            if case .podcast = item {
                label = "Featured show"
            } else {
                label = "Up next"
            }
        } else if selectedCategory == .audiobook {
            label = "Continue the book"
        } else if continueItems.contains(where: { $0.id == item.id }) {
            label = "Pick up"
        } else {
            label = "Made for you"
        }

        return HeroModel(
            display: item.homeHeroDisplay,
            label: label,
            progress: nil,
            isNowPlaying: false,
            item: item
        )
    }

    private var shouldShowNowPlayingHero: Bool {
        switch selectedCategory {
        case .all:
            return true
        case .music:
            return NowPlaying.shared.playbackKind == .music
        case .podcast:
            return NowPlaying.shared.playbackKind == .podcast
        case .audiobook:
            return isCurrentAudiobook
        }
    }

    private var isCurrentAudiobook: Bool {
        let player = NowPlaying.shared
        guard player.queueSongs.indices.contains(player.queueIndex),
              let albumId = player.queueSongs[player.queueIndex].albumId else {
            return false
        }
        return audiobooks.contains { item in
            if case .album(let album) = item { return album.browseId == albumId }
            return false
        }
    }

    /// Bound directly to NowPlaying so the hero follows every track change,
    /// even when the new song is not part of the loaded home feed.
    private var nowPlayingHero: HeroModel? {
        let player = NowPlaying.shared
        guard let videoId = player.videoId,
              !videoId.hasPrefix(NowPlaying.radioPrefix) else { return nil }

        let title = player.displayTitle
        guard !title.isEmpty else { return nil }

        let isPodcast = player.playbackKind == .podcast
        let cover = episodeCovers[videoId]
        let artist = player.displayArtist

        let display = HomeHeroDisplay(
            item: nil,
            title: title,
            subtitle: artist.isEmpty ? (isPodcast ? "Podcast" : "Apollo") : artist,
            kindLabel: isPodcast ? "Episode" : "Song",
            badge: isPodcast ? "Podcast" : nil,
            artworkURL: cover,
            artworkImage: cover == nil ? player.thumbnailUIImage : nil,
            actionSymbol: "play.fill"
        )

        return HeroModel(
            display: display,
            label: "Now playing",
            progress: Double(player.progress),
            isNowPlaying: true,
            item: nil
        )
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
                HomeSectionHeader(kicker: selectedCategory == .all ? "Curated" : selectedCategory.homeKicker, title: "Quick picks", accent: accent)
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

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(quickModels) { model in
                        HomeShelfCard(item: model.item, accent: accent) {
                            tapQuick(model)
                        }
                        .overlay(alignment: .topTrailing) {
                            if model.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(.black.opacity(0.36), in: Circle())
                                    .padding(8)
                            }
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
                .padding(.vertical, 2)
            }
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

    private var genericKeepItems: [YTItem] {
        Array((keepSection?.items ?? []).prefix(12))
    }

    private var genericQuickItems: [YTItem] {
        quickSection?.items ?? []
    }

    private var allHomeItems: [YTItem] {
        var items = viewModel.homeSections.flatMap(\.items)
        items += (viewModel.categoryFeeds[.podcast] ?? []).flatMap(\.items)
        items += (viewModel.categoryFeeds[.audiobook] ?? []).flatMap(\.items)
        items += podcastSuggestions
        return items
    }

    private var podcastEpisodes: [YTItem] {
        dedupeItems(allHomeItems.filter {
            if case .episode = $0 { return true }
            return false
        })
    }

    private var podcastShows: [YTItem] {
        dedupeItems(allHomeItems.filter {
            if case .podcast = $0 { return true }
            return false
        })
    }

    private var audiobooks: [YTItem] {
        dedupeItems(allHomeItems.filter { item in
            if case .album(let album) = item { return album.isAudiobook }
            return false
        })
    }

    private var podcastContinueItems: [YTItem] {
        let preferred = sectionItems(.podcast, keywords: ["keep", "continue", "pick up", "recent", "listening"])
            .filter {
                if case .episode = $0 { return true }
                return false
            }
        let source = dedupeItems(preferred.isEmpty ? podcastEpisodes : preferred)
        let covered = source.filter { podcastCoverURL(for: $0, in: podcastCoverMap) != nil }
        let rest = source.filter { podcastCoverURL(for: $0, in: podcastCoverMap) == nil }
        return Array((covered + rest).prefix(8))
    }

    private var podcastQuickItems: [YTItem] {
        let keepIds = Set(podcastContinueItems.map(\.id))
        let shows = podcastShows.filter { !keepIds.contains($0.id) }
        if !shows.isEmpty { return Array(shows.prefix(10)) }
        return Array(podcastEpisodes.filter { !keepIds.contains($0.id) }.prefix(10))
    }

    private var audiobookContinueItems: [YTItem] {
        let preferred = sectionItems(.audiobook, keywords: ["keep", "continue", "pick up", "listening"])
        let source = preferred.isEmpty ? audiobooks : dedupeItems(preferred)
        return Array(source.prefix(6))
    }

    private var audiobookQuickItems: [YTItem] {
        let keepIds = Set(audiobookContinueItems.map(\.id))
        return Array(audiobooks.filter { !keepIds.contains($0.id) }.prefix(10))
    }

    private var continueItems: [YTItem] {
        switch selectedCategory {
        case .all:
            return Array(dedupeItems(genericKeepItems + podcastContinueItems + audiobookContinueItems).prefix(12))
        case .music:
            return Array(dedupeItems(genericKeepItems.filter { mediaCategory(of: $0) == .music }).prefix(10))
        case .podcast:
            return podcastContinueItems
        case .audiobook:
            return audiobookContinueItems
        }
    }

    private var musicQuickModels: [QuickTileModel] {
        let pinned = speedDialEntries.map {
            QuickTileModel(item: .song($0.toSongItem()), isPinned: true)
        }
        let pinnedIds = Set(pinned.compactMap { $0.item.videoId })

        let others = genericQuickItems.filter { item in
            guard mediaCategory(of: item) == .music else { return false }
            guard let videoId = item.videoId else { return true }
            return !pinnedIds.contains(videoId)
        }.map { QuickTileModel(item: $0, isPinned: false) }

        return Array((pinned + others).prefix(10))
    }

    private var quickModels: [QuickTileModel] {
        switch selectedCategory {
        case .music:
            return musicQuickModels
        case .podcast:
            return podcastQuickItems.map { QuickTileModel(item: $0, isPinned: false) }
        case .audiobook:
            return audiobookQuickItems.map { QuickTileModel(item: $0, isPinned: false) }
        case .all:
            let combined = musicQuickModels
                + podcastQuickItems.map { QuickTileModel(item: $0, isPinned: false) }
                + audiobookQuickItems.map { QuickTileModel(item: $0, isPinned: false) }
            var seen = Set<String>()
            return Array(combined.filter { seen.insert($0.id).inserted }.prefix(12))
        }
    }

    private var musicQuickQueue: [SongItem] {
        let pinned = speedDialEntries.map { $0.toSongItem() }
        let pinnedIds = Set(pinned.map(\.videoId))
        let songs = genericQuickItems.compactMap { item -> SongItem? in
            guard case .song(let song) = item, !pinnedIds.contains(song.videoId) else { return nil }
            return song
        }
        return pinned + songs
    }

    private var quickQueue: [SongItem] {
        selectedCategory == .music ? musicQuickQueue : []
    }

    private var podcastCoverMap: [String: String] {
        var map: [String: String] = [:]
        for case .podcast(let show) in allHomeItems {
            guard let url = show.thumbnailUrl else { continue }
            let titleKey = podcastCoverKey(show.title)
            if titleKey.count >= 4 { map[titleKey] = url }
            if let author = show.author {
                let authorKey = podcastCoverKey(author)
                if authorKey.count >= 4 { map[authorKey] = url }
            }
        }
        for (videoId, cover) in episodeCovers {
            map["vid:\(videoId)"] = cover
        }
        return map
    }

    private func loadPodcastEpisodeCovers() async {
        let shows = podcastShows.compactMap { item -> PodcastItem? in
            if case .podcast(let show) = item { return show }
            return nil
        }
        let pending = shows.filter { !fetchedShowIds.contains($0.browseId) }.prefix(8)
        guard !pending.isEmpty else { return }

        var covers = episodeCovers
        var fetched = fetchedShowIds
        for show in pending {
            fetched.insert(show.browseId)
            guard let json = try? await InnerTubeClient.apolloShared.browse(browseId: show.browseId).value else {
                continue
            }
            let detail = PodcastDetailViewModel.parsePodcastDetail(from: json, browseId: show.browseId)
            guard let cover = detail.thumbnailUrl else { continue }
            for episode in detail.episodes {
                covers[episode.videoId] = cover
            }
        }
        fetchedShowIds = fetched
        episodeCovers = covers
    }

    private func mediaCategory(of item: YTItem) -> ContentCategory {
        switch item {
        case .episode, .podcast:
            return .podcast
        case .album(let album) where album.isAudiobook:
            return .audiobook
        default:
            return .music
        }
    }

    private func dedupeItems(_ items: [YTItem]) -> [YTItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func sectionItems(_ category: ContentCategory, keywords: [String]) -> [YTItem] {
        for section in (viewModel.categoryFeeds[category] ?? []) {
            let title = section.title.lowercased()
            guard keywords.contains(where: { title.contains($0) }) else { continue }
            let items = section.items.filter { mediaCategory(of: $0) == category }
            if !items.isEmpty { return dedupeItems(items) }
        }
        return []
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

    private func openPlayer() {
        PlayerSheetState.shared.hasExpandedArtwork = !NowPlaying.shared.isVideoMode
        withAnimation(.smooth(duration: 0.3)) {
            PlayerSheetState.shared.isExpanded = true
        }
    }

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
            let queue = musicQuickQueue.isEmpty ? [song] : musicQuickQueue
            handleSongTap(song, in: queue)
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
