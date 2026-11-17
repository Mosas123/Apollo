//
//  SearchView.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import SwiftUI

private struct SearchBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SearchView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var viewModel = SearchViewModel()
    @ObservedObject private var router = AppRouter.shared
    @FocusState private var fieldFocused: Bool

    @State private var pendingRoute: DetailRoute?
    @State private var headerHidden = false
    @State private var headerHeight: CGFloat = 60
    @State private var searchBarHeight: CGFloat = 60
    private let accountState = AccountSheetState.shared

    var body: some View {
        NavigationStack(path: $router.searchPath) {
            ZStack(alignment: .top) {
                content
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Color.clear.frame(height: searchBarHeight + (isSearchActive ? 0 : headerHeight))
                    }

                VStack(spacing: 0) {
                    if !isSearchActive {
                        TabHeaderView(
                            title: "Search",
                            accountIsLoggedIn: accountState.isLoggedIn,
                            accountImageUrl: accountState.accountImageUrl,
                            onAccount: { router.searchPath.append(DetailRoute.settings) },
                            accountInitial: accountState.accountName.first.map(String.init)
                        )
                        .opacity(headerHidden ? 0 : 1)
                        .allowsHitTesting(!headerHidden)
                        .accessibilityHidden(headerHidden)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: TabHeaderMeasurementKey.self, value: geometry.size.height)
                            }
                        }
                        .onPreferenceChange(TabHeaderMeasurementKey.self) { if $0 > 0 { headerHeight = $0 } }
                    }
                    searchTopBar
                        .background {
                            Color(.systemBackground)
                                .ignoresSafeArea(.container, edges: .top)
                                .allowsHitTesting(false)
                        }
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: SearchBarHeightKey.self, value: geometry.size.height)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onPreferenceChange(SearchBarHeightKey.self) { if $0 > 0 { searchBarHeight = $0 } }
                }
                .offset(y: !isSearchActive && headerHidden ? -headerHeight : 0)
                .zIndex(1)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .detailRouteDestinations()
            .onChange(of: pendingRoute) { _, route in
                if let route {
                    router.searchPath.append(route)
                    pendingRoute = nil
                }
            }
            .onAppear {
                viewModel.loadSearchHistory()
            }
            .onChange(of: router.selectedTabIndex) { _, selectedTab in
                if selectedTab != 3 { fieldFocused = false }
            }
            .task(id: viewModel.results.count) {
                let urls = viewModel.results
                    .flatMap(\.items)
                    .compactMap(\.thumbnailUrl)
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
        }
    }

    // MARK: - Top bar

    private var isSearchActive: Bool {
        fieldFocused || !viewModel.fieldText.isEmpty || viewModel.phase != .idle
    }

    /// Search field and cancel control pinned above the filter chips.
    private var searchTopBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $viewModel.fieldText)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { submit(nil) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())

            if isSearchActive {
                Button {
                    fieldFocused = false
                    viewModel.closeSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            if viewModel.searchHistory.isEmpty {
                noRecentSearchesView
            } else {
                searchHistoryView
            }
        case .loading:
            liveSearchStatus {
                if viewModel.isFetching {
                    ProgressView().padding()
                }
            }
        case .results:
            searchResultsList
        case .noResults:
            liveSearchStatus { noResultsView }
        case .failed:
            liveSearchStatus { errorView(viewModel.error) }
        }
    }

    private func liveSearchStatus<Status: View>(@ViewBuilder status: () -> Status) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                suggestionRows
                status().frame(maxWidth: .infinity)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var suggestionRows: some View {
        ForEach(viewModel.suggestions, id: \.self) { suggestion in
            Button {
                submit(suggestion)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(suggestion)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 16)
        }
    }

    // MARK: - Submission

    private func submit(_ text: String? = nil) {
        if let text {
            viewModel.fieldText = text
        }
        fieldFocused = false
        viewModel.submit()
    }

    private var searchHistoryView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recently searched")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Clear") {
                        viewModel.clearSearchHistory()
                    }
                    .font(.subheadline)
                    .foregroundColor(settings.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ForEach(viewModel.searchHistory, id: \.query) { entry in
                    Button {
                        submit(entry.query)
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .foregroundColor(settings.accentColor)
                            Text(entry.query)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.deleteSearchHistoryEntry(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll(headerHidden: $headerHidden).scrollEdgeEffectHidden(true, for: .bottom)
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                suggestionRows
                if !viewModel.availableFilters.isEmpty {
                    filterChips
                }

                if let hero = viewModel.heroArtist {
                    artistHeroCard(hero, songs: viewModel.heroSongs)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                ForEach(viewModel.filteredResults) { section in
                    sectionHeader(section.title)

                    switch section.title {
                    case "Artists":
                        artistCarousel(items: section.items)
                    case "Albums":
                        albumCarousel(items: section.items)
                    default:
                        ForEach(section.items, id: \.id) { item in
                            YouTubeListItemView(item: item, onTap: {
                                handleItemTap(item)
                            }, onNavigate: { pendingRoute = $0 })
                        }
                    }
                }

                if viewModel.showsAudiusResults && !viewModel.audiusTracks.isEmpty {
                    sectionHeader("Audius")
                    ForEach(viewModel.audiusTracks, id: \.id) { track in
                        externalTrackRow(track, from: viewModel.audiusTracks)
                    }
                }

                if viewModel.showsQobuzResults && !viewModel.qobuzTracks.isEmpty {
                    sectionHeader("Qobuz")
                    ForEach(viewModel.qobuzTracks, id: \.id) { track in
                        externalTrackRow(track, from: viewModel.qobuzTracks)
                    }
                }

                if viewModel.showsPencariResults && !viewModel.pencariTracks.isEmpty {
                    sectionHeader("Lossless")
                    ForEach(viewModel.pencariTracks, id: \.id) { track in
                        externalTrackRow(track, from: viewModel.pencariTracks)
                    }
                }

                if viewModel.showsJioSaavnResults && !viewModel.jiosaavnTracks.isEmpty {
                    sectionHeader("JioSaavn")
                    ForEach(viewModel.jiosaavnTracks, id: \.id) { track in
                        externalTrackRow(track, from: viewModel.jiosaavnTracks)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll(headerHidden: $headerHidden).scrollEdgeEffectHidden(true, for: .bottom)
    }

    /// Play external-catalogue tracks using the provider-scoped queue adapter.
    /// Do not expose YouTube's song menu or navigation actions on this row.
    private func externalTrackRow(_ track: MusicCatalogTrack, from tracks: [MusicCatalogTrack]) -> some View {
        Button {
            let songs = tracks.map { $0.asQueueSong() }
            PlaybackQueue.play(
                track.asQueueSong(), in: songs, log: Log.searchView,
                context: "\(track.id.source.rawValue) search"
            )
        } label: {
            HStack(spacing: 12) {
                AsyncImageView(url: track.artworkURL?.absoluteString)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .foregroundStyle(settings.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Section title with chevron — taps drill into (or clear) the filter.
    private func sectionHeader(_ title: String) -> some View {
        Button {
            if viewModel.selectedSectionFilter == title {
                viewModel.selectedSectionFilter = nil
            } else {
                viewModel.selectedSectionFilter = title
                viewModel.isShowingLibrary = false
            }
        } label: {
            HStack(spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    /// Artist-first hero: big circular artwork + name, then top songs.
    private func artistHeroCard(_ artist: ArtistItem, songs: [SongItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                router.searchPath.append(DetailRoute.artist(browseId: artist.browseId))
            } label: {
                HStack(spacing: 12) {
                    AsyncImageView(url: artist.thumbnailUrl)
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    Text(artist.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text("•••")
                        .font(.body.weight(.black))
                        .foregroundStyle(settings.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ForEach(songs, id: \.videoId) { song in
                let item = YTItem.song(song)
                YouTubeListItemView(item: item, onTap: {
                    handleItemTap(item)
                }, onNavigate: { pendingRoute = $0 })
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func artistCarousel(items: [YTItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(items, id: \.id) { item in
                    if case .artist(let artist) = item {
                        Button {
                            router.searchPath.append(DetailRoute.artist(browseId: artist.browseId))
                        } label: {
                            VStack(spacing: 8) {
                                AsyncImageView(url: artist.thumbnailUrl)
                                    .frame(width: 110, height: 110)
                                    .clipShape(Circle())
                                Text(artist.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 110)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func albumCarousel(items: [YTItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items, id: \.id) { item in
                    if case .album(let album) = item {
                        Button {
                            router.searchPath.append(DetailRoute.album(browseId: album.browseId))
                        } label: {
                            MediaGridCell(
                                thumbnailUrl: album.thumbnailUrl,
                                title: album.title,
                                subtitle: album.artists.map(\.name).joined(separator: ", "),
                                size: 140
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu { AlbumContextMenu(album: album) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var filterChips: some View {
        FilterChipBar(
            items: ["All Results"] + viewModel.availableFilters,
            id: \.self,
            title: { $0 },
            isSelected: { filter in
                if filter == "All Results" {
                    return viewModel.selectedSectionFilter == nil && !viewModel.isShowingLibrary
                }
                return filter == "Library"
                    ? viewModel.isShowingLibrary
                    : viewModel.selectedSectionFilter == filter
            },
            onTap: { filter in
                if filter == "All Results" {
                    viewModel.selectedSectionFilter = nil
                    viewModel.isShowingLibrary = false
                } else if filter == "Library" {
                    let willShow = !viewModel.isShowingLibrary
                    viewModel.isShowingLibrary = willShow
                    viewModel.selectedSectionFilter = nil
                } else {
                    viewModel.selectedSectionFilter = filter
                    viewModel.isShowingLibrary = false
                }
            }
        )
    }

    private var noResultsView: some View {
        ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("No results found for \"\(viewModel.submittedQuery)\"")
        )
    }

    private var noRecentSearchesView: some View {
        ContentUnavailableView(
            "No Recent Searches",
            systemImage: "magnifyingglass",
            description: Text("Your recent searches will appear here.")
        )
    }

    private func errorView(_ error: Error?) -> some View {
        ContentUnavailableView(
            "Search failed",
            systemImage: "exclamationmark.triangle",
            description: Text(error?.localizedDescription ?? "Something went wrong.")
        )
    }

    private func handleItemTap(_ item: YTItem) {
        YTItemRouter.route(
            item,
            playSong: { PlaybackQueue.playSingleWithRadio($0, log: Log.searchView) },
            appendRoute: { router.searchPath.append($0) }
        )
    }
}
