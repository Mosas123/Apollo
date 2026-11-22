//
// ExploreView.swift
// Trop
//
// Created by 686udjie on 11/09/2026.
//

import SwiftUI

struct ExploreView: View {
    @State private var viewModel = ExploreViewModel()
    @ObservedObject private var router = AppRouter.shared

    @State private var pendingRoute: DetailRoute?

    private let accountState = AccountSheetState.shared
    @AppStorage("trop.library.v2.previewEnabled")
    private var libraryV2PreviewEnabled = false

    var body: some View {
        NavigationStack(path: $router.explorePath) {
            VStack(spacing: 0) {
                TabHeaderView(
                    title: "Explore",
                    accountIsLoggedIn: !libraryV2PreviewEnabled && accountState.isLoggedIn,
                    accountImageUrl: libraryV2PreviewEnabled ? nil : accountState.accountImageUrl,
                    onAccount: { router.explorePath.append(DetailRoute.settings) }
                )

                if libraryV2PreviewEnabled {
                    v2AudioExplore
                } else {
                    content
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .detailRouteDestinations()
            .navigationDestination(for: MoodItem.self) { mood in
                MoodDetailView(mood: mood)
            }
            .onChange(of: pendingRoute) { _, route in
                if let route {
                    router.explorePath.append(route)
                    pendingRoute = nil
                }
            }
            .onAppear {
                if !libraryV2PreviewEnabled { viewModel.load() }
            }
            .onChange(of: libraryV2PreviewEnabled) { _, enabled in
                if !enabled { viewModel.load() }
            }
            .task {
                guard !libraryV2PreviewEnabled else { return }
                await accountState.restoreSession()
                await accountState.fetchAccountInfo()
            }
            .task(id: viewModel.sections.count) {
                guard !libraryV2PreviewEnabled else { return }
                let urls = viewModel.sections
                    .flatMap(\.items)
                    .compactMap(\.thumbnailUrl)
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
        }
    }

    // MARK: - Content

    /// The previous Explore shelves and mood feeds came exclusively from
    /// YouTube Music. Do not relabel those as Trop's catalogue. While our
    /// own discovery index is built, route users to the independent audio
    /// provider search instead of fetching any InnerTube feed.
    private var v2AudioExplore: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Explore audio", systemImage: "music.magnifyingglass")
                    .font(.title2.weight(.bold))
                Text(
                    "Trop no longer uses YouTube Music's catalogue here. "
                        + "Discover tracks from available audio providers through Search."
                )
                .foregroundStyle(.secondary)
                Button {
                    router.selectedTabIndex = 3
                } label: {
                    Label("Search music", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    router.selectedTabIndex = 2
                } label: {
                    Label("Your library", systemImage: "music.note.list")
                }
                .buttonStyle(.bordered)
                Text("Independent charts and recommendations are still being built.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .miniPlayerTracksScroll()
        .scrollEdgeEffectHidden(true, for: .bottom)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            ExploreSkeletonView()
        case .loaded:
            sectionsList
        case .empty:
            ContentUnavailableView(
                "Nothing to explore",
                systemImage: "flame",
                description: Text("Try again later.")
            )
        case .failed:
            ContentUnavailableView(
                "Explore failed",
                systemImage: "exclamationmark.triangle",
                description: Text("Couldn't load Explore. Pull to retry.")
            )
        }
    }

    private var sectionsList: some View {
        ScrollView {
            ExploreSectionsList(sections: viewModel.sections, pendingRoute: $pendingRoute)
                .padding(.bottom, 16)
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll().scrollEdgeEffectHidden(true, for: .bottom)
        .refreshable { await viewModel.refresh() }
    }
}

// MARK: - Shared section list

/// Renders Explore sections (song grids, card carousels, mood grids).
/// Shared by the Explore tab and mood category pages.
struct ExploreSectionsList: View {
    @ObservedObject private var router = AppRouter.shared
    var sections: [ExploreSection]
    var pendingRoute: Binding<DetailRoute?>

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(sections) { section in
                switch section.kind {
                case .rows:
                    songGrid(section)
                case .cards:
                    cardsCarousel(section)
                case .moods:
                    moodsGrid(section)
                }
            }
        }
        .onAppear {
            Log.explore.debug(
                "Render sections: " +
                sections.map { "\($0.title)(\($0.kind)):\($0.items.count)" }.joined(separator: ", ")
            )
        }
    }

    // MARK: - Rows

    /// Song rows in a 4-row grid scrolling horizontally.
    private func songGrid(_ section: ExploreSection) -> some View {
        HorizontalSection(title: section.title) {
            LazyHGrid(
                rows: [
                    GridItem(.flexible(), spacing: 0),
                    GridItem(.flexible(), spacing: 0),
                    GridItem(.flexible(), spacing: 0),
                    GridItem(.flexible(), spacing: 0)
                ],
                spacing: 12
            ) {
                ForEach(section.items, id: \.id) { item in
                    YouTubeListItemView(item: item, onTap: {
                        openItem(item)
                    }, onNavigate: { pendingRoute.wrappedValue = $0 })
                    .frame(width: 320, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Cards carousel

    private func cardsCarousel(_ section: ExploreSection) -> some View {
        HorizontalSection(title: section.title) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(section.items, id: \.id) { item in
                    YouTubeGridItemView(item: item, onTap: {
                        openItem(item)
                    })
                }
            }
        }
    }

    // MARK: - Moods grid

    private func moodsGrid(_ section: ExploreSection) -> some View {
        HorizontalSection(title: section.title) {
            // Two-row grid scrolling horizontally: all 50+ moods reachable
            // without a dominating vertical wall.
            LazyHGrid(
                rows: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(section.moods) { mood in
                    NavigationLink(value: mood) {
                        Text(LocalizedStringKey(mood.title))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: 150)
                            .frame(minHeight: 64)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5).opacity(0.6))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Navigation & playback

    private func openItem(_ item: YTItem) {
        YTItemRouter.route(
            item,
            playSong: { PlaybackQueue.playSingleWithRadio($0, log: Log.explore) },
            appendRoute: { router.explorePath.append($0) }
        )
    }
}

// MARK: - Mood detail

/// Full mood/genre category page: songs grid, playlists, videos, albums.
private struct MoodDetailView: View {
    let mood: MoodItem

    @State private var sections: [ExploreSection]?
    @State private var pendingRoute: DetailRoute?

    var body: some View {
        Group {
            if let sections {
                if sections.isEmpty {
                    ContentUnavailableView(
                        "Nothing here",
                        systemImage: "square.grid.2x2",
                        description: Text(AppStrings.format("Nothing found for %@.", NSLocalizedString(mood.title, comment: "Mood name")))
                    )
                } else {
                    ScrollView {
                        ExploreSectionsList(sections: sections, pendingRoute: $pendingRoute)
                            .padding(.bottom, 16)
                    }
                    .scrollIndicators(.automatic)
                    .miniPlayerTracksScroll().scrollEdgeEffectHidden(true, for: .bottom)
                }
            } else {
                MoodDetailSkeletonView()
            }
        }
        .navigationTitle(mood.title)
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: pendingRoute) { _, route in
            if let route {
                AppRouter.shared.explorePath.append(route)
                pendingRoute = nil
            }
        }
        .task {
            sections = await ExploreViewModel.loadMoodDetail(mood)
        }
    }
}

// MARK: - Explore tab skeleton

/// Loading placeholder mirroring the Explore tab: album cards (title only),
/// the 2-row moods grid, then a vertical Trending song list — the same
/// shimmer animation as Home, composed for this layout.
private struct ExploreSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    ShimmerSectionTitle(width: 220)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                ShimmerCard(showsSubtitle: false)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ShimmerSectionTitle(width: 160)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHGrid(
                            rows: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(0..<10, id: \.self) { _ in
                                ShimmerBlock(width: 150, height: 64, radius: 12)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ShimmerSectionTitle(width: 120)
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { _ in
                            ShimmerRow()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Mood detail skeleton

/// Loading placeholder mirroring the mood page layout: a vertical song
/// list followed by large playlist cards.
private struct MoodDetailSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    ShimmerSectionTitle(width: 80)
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: 12) {
                                ShimmerRow(titleWidth: 190, subtitleWidth: 130)
                                ShimmerBlock(width: 90, height: 20, radius: 4)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                    }
                }
                skeletonCardsSection(titleWidth: 200)
                skeletonCardsSection(titleWidth: 220)
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func skeletonCardsSection(titleWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ShimmerSectionTitle(width: titleWidth)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShimmerCard(showsSubtitle: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }
}
