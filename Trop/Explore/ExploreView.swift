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
    @State private var v2ArtistSeeds: [String] = []
    @State private var selectedV2Artist: String?
    @State private var v2DiscoveredTracks: [MusicCatalogTrack] = []
    @State private var isLoadingV2Artists = false
    @State private var isSearchingV2Artist = false
    @State private var v2ExploreMessage: String?

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

    /// Explore V2 never loads YouTube Music's browse feeds. Artists come
    /// from saved Trop UUID metadata; audio candidates are queried only after
    /// an explicit tap, from enabled, independent source providers.
    private var v2AudioExplore: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Label("Explore audio", systemImage: "music.magnifyingglass")
                    .font(.title2.weight(.bold))
                Text(
                    "Browse artists from your Trop library and discover "
                        + "audio from independent providers. No YouTube Music catalogue."
                )
                .foregroundStyle(.secondary)

                if isLoadingV2Artists {
                    ProgressView("Reading saved artists…")
                } else if v2ArtistSeeds.isEmpty {
                    Text("Save a song or artist to start exploring from your library.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Artists from your library").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(v2ArtistSeeds, id: \.self) { artist in
                                Button(artist) {
                                    guard selectedV2Artist != artist else { return }
                                    v2DiscoveredTracks = []
                                    selectedV2Artist = artist
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedV2Artist == artist ? .accentColor : .secondary)
                            }
                        }
                    }
                }

                if let selectedV2Artist {
                    Text("From audio providers · " + selectedV2Artist)
                        .font(.headline)
                    if isSearchingV2Artist {
                        ProgressView("Searching enabled audio providers…")
                    } else if v2DiscoveredTracks.isEmpty {
                        Text("No matching playable candidates found. Try another artist.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(v2DiscoveredTracks, id: \.id) { track in
                            Button {
                                let group = v2DiscoveredTracks.filter {
                                    $0.id.source == track.id.source
                                }.map { $0.asQueueSong() }
                                PlaybackQueue.play(
                                    track.asQueueSong(), in: group,
                                    log: Log.explore,
                                    context: "independent explore"
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImageView(url: track.artworkURL?.absoluteString)
                                        .frame(width: 50, height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                        Text(track.id.source == .addon
                                             ? "Music Add-on"
                                             : track.id.source.rawValue.capitalized)
                                            .foregroundStyle(.secondary)
                                            .font(.caption2)
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill")
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let v2ExploreMessage {
                    Text(v2ExploreMessage)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                Text(
                    "These are provider search candidates, not official charts "
                        + "or personalized recommendations. Streams and quality "
                        + "are verified when playback starts."
                )
                .font(.footnote)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .task { await loadV2ArtistSeeds() }
        .task(id: selectedV2Artist) {
            guard libraryV2PreviewEnabled, let artist = selectedV2Artist else {
                return
            }
            isSearchingV2Artist = true
            let matches = await ExploreV2ProviderDiscovery.tracks(for: artist)
            guard !Task.isCancelled, libraryV2PreviewEnabled,
                  selectedV2Artist == artist else { return }
            v2DiscoveredTracks = matches
            isSearchingV2Artist = false
        }
        .miniPlayerTracksScroll()
        .scrollEdgeEffectHidden(true, for: .bottom)
    }

    @MainActor
    private func loadV2ArtistSeeds() async {
        guard libraryV2PreviewEnabled else { return }
        isLoadingV2Artists = true
        do {
            async let saved = TropLibraryV2Store.recordings()
            async let artists = TropLibraryV2Store.savedCatalogItems(kind: .artist)
            let (recordings, artistItems) = try await (saved, artists)
            guard !Task.isCancelled, libraryV2PreviewEnabled else { return }
            v2ArtistSeeds = ExploreV2DiscoveryPolicy.artistSeeds(
                artistItems.map { Optional($0.title) }
                    + recordings.map(\.artist)
            )
            v2ExploreMessage = nil
        } catch {
            v2ArtistSeeds = []
            v2ExploreMessage = "Could not load saved artists. Your library was not changed."
        }
        isLoadingV2Artists = false
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
