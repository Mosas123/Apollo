//
//  AlbumDetailView.swift
//  Apollo
//
//  Created by 686udjie on 03/07/2026.
//

@preconcurrency import ApolloTube
import SwiftUI
import UIKit

// MARK: - View Model

@MainActor
@Observable
final class AlbumDetailViewModel {
    let browseId: String
    var album: AlbumDetailInfo?
    var isLoading = true
    var error: Error?
    var isSaved = false

    private let innerTube = InnerTubeClient.apolloShared

    init(browseId: String) {
        self.browseId = browseId
    }

    /// Fetches album browse page from InnerTube and parses the response.
    func load() async {
        Log.albumDetailViewModel.debug("Loading album browseId=\(browseId)")
        isLoading = true
        error = nil

        if SpotifyCatalogID.isAudiobook(browseId) || SpotifyCatalogID.isSpotify(browseId) {
            do {
                let id = SpotifyCatalogID.rawID(browseId) ?? browseId
                album = SpotifyCatalogID.isAudiobook(browseId)
                    ? try await SpotifyDetailService.shared.audiobookDetail(id: id)
                    : try await SpotifyDetailService.shared.albumDetail(id: id)
                isLoading = false
                await refreshSavedState()
            } catch {
                Log.albumDetailViewModel.error("Spotify album failed: \(error)")
                self.error = error
                isLoading = false
            }
            return
        }

        do {
            let json = try await innerTube.browse(browseId: browseId).value
            Log.albumDetailViewModel.debug("Got browse response, parsing...")
            let parsed = Self.parseAlbumDetail(from: json, browseId: browseId)
            album = parsed
            Log.albumDetailViewModel.debug("Parsed album: \(parsed.title), \(parsed.songs.count) songs")
            isLoading = false
            await refreshSavedState()
            if let name = parsed.artists.first?.name,
               let artwork = await MetadataResolver.albumArtwork(title: parsed.title, artist: name),
               !Task.isCancelled, album?.browseId == parsed.browseId {
                album?.thumbnailUrl = artwork.absoluteString
            }
        } catch {
            Log.albumDetailViewModel.error("Failed: \(error)")
            self.error = error
            isLoading = false
        }
    }

    func refreshSavedState() async {
        let entity = try? await DatabaseService.shared.fetchOne(AlbumEntity.self, key: browseId)
        isSaved = entity?.bookmarkedAt != nil
    }

    func toggleSave() async {
        guard let album else { return }
        let currentlySaved = isSaved
        isSaved = !currentlySaved

        do {
            if currentlySaved {
                if let entity = try? await DatabaseService.shared.fetchOne(
                    AlbumEntity.self,
                    key: browseId
                ) {
                    try await DatabaseService.shared.delete(entity)
                }
            } else {
                try await DatabaseService.shared.save(
                    AlbumEntity(
                        id: browseId,
                        title: album.title,
                        playlistId: nil,
                        thumbnailUrl: album.thumbnailUrl,
                        songCount: album.songCount,
                        duration: album.duration,
                        bookmarkedAt: Date()
                    )
                )
            }
            NotificationCenter.default.post(
                name: Notification.Name("apollo.libraryChanged"),
                object: nil
            )
        } catch {
            Log.albumDetailViewModel.error("Album save failed: \(error)")
        }
        await refreshSavedState()
    }
}

// MARK: - Parser

extension AlbumDetailViewModel {
    // swiftlint:disable cyclomatic_complexity
    /// Parses InnerTube browse JSON into an AlbumDetailInfo.
    /// Extracts header metadata (title, artists, year, song count, duration, thumbnail)
    /// from musicDetailHeaderRenderer and songs from musicPlaylistShelfRenderer.
    /// Branch count is inherent to tolerant InnerTube JSON parsing.
    static func parseAlbumDetail(from json: [String: Any], browseId: String) -> AlbumDetailInfo {
        var title = "Unknown Album"
        var artists: [YTArtist] = []
        var year: Int?
        var songCount = 0
        var duration = 0
        var thumbnailUrl: String?
        var playlistId: String?
        var songs: [SongItem] = []
        var descriptionText: String?
        var relatedAlbums: [AlbumItem] = []
        var videos: [SongItem] = []
        var featuredPlaylists: [PlaylistItem] = []

        // Resolve first tab section (exists in both layouts)
        let firstTabSection: [String: Any]? = BrowseLens.firstSectionItem(json)

        // --- Header: musicResponsiveHeaderRenderer (modern two-column albums) ---
        if let responsiveHeader = firstTabSection?["musicResponsiveHeaderRenderer"] as? [String: Any] {
            title = InnerTubeJSON.runsText(responsiveHeader["title"] as? [String: Any]) ?? title

            // Artists from straplineTextOne
            if let strapline = responsiveHeader["straplineTextOne"] as? [String: Any],
               let runs = strapline["runs"] as? [[String: Any]] {
                artists = ArtistCredits.parse(runs: runs).map { YTArtist(name: $0.name, id: $0.browseId) }
            }
            // Artist fallback from subtitle runs
            if artists.isEmpty,
               let subtitle = responsiveHeader["subtitle"] as? [String: Any],
               let runs = subtitle["runs"] as? [[String: Any]] {
                artists = ArtistCredits.parse(runs: runs).map { YTArtist(name: $0.name, id: $0.browseId) }
            }

            // Year / songCount / duration from secondSubtitle
            if let secondSubtitle = responsiveHeader["secondSubtitle"] as? [String: Any],
               let runs = secondSubtitle["runs"] as? [[String: Any]] {
                for run in runs {
                    guard let text = run["text"] as? String else { continue }
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if let yearVal = Int(trimmed), trimmed.count == 4, yearVal > 1900, yearVal < 2100 {
                        year = yearVal
                    } else if trimmed.contains("song") || trimmed.contains("Song") ||
                              trimmed.contains("track") || trimmed.contains("Track") {
                        let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
                        if let count = nums.first { songCount = count }
                    } else if trimmed.contains(":") {
                        duration = DurationFormat.parseClock(trimmed) ?? 0
                    }
                }
            }

            thumbnailUrl = InnerTubeJSON.musicThumbnailURL(responsiveHeader)

            if descriptionText == nil,
               let descDict = responsiveHeader["description"] as? [String: Any] {
                let shelf = descDict["musicDescriptionShelfRenderer"] as? [String: Any]
                descriptionText = (shelf?["description"] as? [String: Any]).flatMap { InnerTubeJSON.runsText($0) }
                    ?? InnerTubeJSON.runsText(descDict)
            }
        }

        // --- Header fallback: musicDetailHeaderRenderer (legacy / single-column) ---
        if title == "Unknown Album" {
            let legacyHeader: [String: Any]? =
                (json["header"] as? [String: Any])?["musicDetailHeaderRenderer"] as? [String: Any]

            if let detailHeader = legacyHeader {
                title = InnerTubeJSON.runsText(detailHeader["title"] as? [String: Any]) ?? title

                if let subtitle = detailHeader["subtitle"] as? [String: Any],
                   let runs = subtitle["runs"] as? [[String: Any]] {
                    artists += ArtistCredits.parse(runs: runs).map { YTArtist(name: $0.name, id: $0.browseId) }
                }

                if let secondSubtitle = detailHeader["secondSubtitle"] as? [String: Any],
                   let runs = secondSubtitle["runs"] as? [[String: Any]] {
                    for run in runs {
                        guard let text = run["text"] as? String else { continue }
                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                        if let yearVal = Int(trimmed), trimmed.count == 4, yearVal > 1900, yearVal < 2100 {
                            year = yearVal
                        } else if trimmed.contains("song") || trimmed.contains("Song") ||
                                  trimmed.contains("track") || trimmed.contains("Track") {
                            let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
                            if let count = nums.first { songCount = count }
                        } else if trimmed.contains(":") {
                            duration = DurationFormat.parseClock(trimmed) ?? 0
                        }
                    }
                }

                if thumbnailUrl == nil { thumbnailUrl = InnerTubeJSON.musicThumbnailURL(detailHeader) }

                // Extract playlistId from menu items (needed for playback queue)
                if let menu = detailHeader["menu"] as? [String: Any],
                   let menuRenderer = menu["menuRenderer"] as? [String: Any],
                   let items = menuRenderer["items"] as? [[String: Any]] {
                    for item in items {
                        if let menuNav = item["menuNavigationItemRenderer"] as? [String: Any],
                           let nav = menuNav["navigationEndpoint"] as? [String: Any],
                           let watch = nav["watchEndpoint"] as? [String: Any],
                           let pid = watch["playlistId"] as? String {
                            playlistId = pid
                        }
                    }
                }
            }
        }

        // Fallback: extract playlistId from microformat URL query parameter
        // URL format: https://music.youtube.com/playlist?list=OLAK5uy_...
        if playlistId == nil,
           let microformat = json["microformat"] as? [String: Any],
           let mfRenderer = microformat["microformatDataRenderer"] as? [String: Any],
           let urlCanonical = mfRenderer["urlCanonical"] as? String,
           let components = URLComponents(string: urlCanonical) {
            if let listParam = components.queryItems?.first(where: { $0.name == "list" })?.value {
                playlistId = listParam
            }
        }

        // --- Songs ---
        // Album track rows carry no per-row thumbnail; fall back to the album art (same as Metrolist).
        func parseSongsFromShelf(_ shelfDict: [String: Any], fallbackThumbnail: String?) -> [SongItem] {
            var result: [SongItem] = []
            let albumArtists = artists
            let items: [[String: Any]]? =
                (shelfDict["musicPlaylistShelfRenderer"] as? [String: Any])?["contents"] as? [[String: Any]]
                ?? (shelfDict["musicShelfRenderer"] as? [String: Any])?["contents"] as? [[String: Any]]
            for itemDict in items ?? [] {
                if let renderer = itemDict["musicResponsiveListItemRenderer"] as? [String: Any],
                   var song = SongItem.from(renderer) {
                    if song.thumbnailUrl == nil { song.thumbnailUrl = fallbackThumbnail }
                    // Album track rows often only show the track title. The
                    // header owns the artist credit, so carry it into every
                    // track instead of letting the player show a blank artist.
                    if song.artists.isEmpty || artistDisplayString(from: song.artists).isEmpty {
                        song.artists = albumArtists
                    }
                    if song.album == nil { song.album = title }
                    if song.albumId == nil { song.albumId = browseId }
                    if song.year == nil { song.year = year }
                    result.append(song)
                }
            }
            return result
        }

        func classifyCarousel(_ section: [String: Any]) {
            guard let carousel = section["musicCarouselShelfRenderer"] as? [String: Any],
                  let contents = carousel["contents"] as? [[String: Any]] else { return }
            for itemDict in contents {
                guard let twoRow = itemDict["musicTwoRowItemRenderer"] as? [String: Any] else { continue }
                let pageType = HomePageParser.extractPageType(twoRow)
                switch pageType {
                case "MUSIC_PAGE_TYPE_ALBUM", "MUSIC_PAGE_TYPE_AUDIOBOOK":
                    if let album = AlbumItem.from(twoRow), album.browseId != browseId {
                        relatedAlbums.append(album)
                    }
                case "MUSIC_PAGE_TYPE_PLAYLIST":
                    if let playlist = PlaylistItem.from(twoRow) {
                        featuredPlaylists.append(playlist)
                    }
                default:
                    let isVideoPage = pageType == "MUSIC_PAGE_TYPE_VIDEO"
                    let hasWatchEndpoint = HomePageParser.hasWatchEndpoint(twoRow)
                    if isVideoPage || hasWatchEndpoint, let video = SongItem.from(twoRow) {
                        videos.append(video)
                    }
                }
            }
        }

        func captureDescription(_ section: [String: Any]) {
            guard descriptionText == nil,
                  let shelf = section["musicDescriptionShelfRenderer"] as? [String: Any],
                  let desc = (shelf["description"] as? [String: Any]).flatMap({ InnerTubeJSON.runsText($0) }),
                  !desc.isEmpty else { return }
            descriptionText = desc
        }

        if let twoCol = (json["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any] {
            // Songs are in secondaryContents for two-column albums
            if let secondary = twoCol["secondaryContents"] as? [String: Any],
               let sectionList = secondary["sectionListRenderer"] as? [String: Any],
               let secondarySections = sectionList["contents"] as? [[String: Any]] {
                for section in secondarySections {
                    songs += parseSongsFromShelf(section, fallbackThumbnail: thumbnailUrl)
                    classifyCarousel(section)
                    captureDescription(section)
                }
            }
            // Fallback: songs might still be in first tab section (e.g. musicShelfRenderer)
            if songs.isEmpty, let firstSection = firstTabSection {
                songs += parseSongsFromShelf(firstSection, fallbackThumbnail: thumbnailUrl)
            }
        } else if let sections = BrowseLens.browseSections(json) {
            for section in sections {
                songs += parseSongsFromShelf(section, fallbackThumbnail: thumbnailUrl)
                classifyCarousel(section)
                captureDescription(section)
            }
        }

        // Some album headers omit the artist credit. Derive it from the first
        // track that has one and propagate to the rest.
        if artists.isEmpty, let fallback = songs.first(where: { !$0.artists.isEmpty })?.artists {
            artists = fallback
            for index in songs.indices where songs[index].artists.isEmpty {
                songs[index].artists = fallback
            }
        }

        // Set songCount from actual count if header value wasn't parsed
        if songCount == 0 { songCount = songs.count }

        return AlbumDetailInfo(
            title: title,
            artists: artists,
            year: year,
            songCount: songCount,
            duration: duration,
            thumbnailUrl: thumbnailUrl,
            playlistId: playlistId,
            browseId: browseId,
            songs: songs,
            descriptionText: descriptionText,
            relatedAlbums: relatedAlbums,
            videos: videos,
            featuredPlaylists: featuredPlaylists
        )
    }
    // swiftlint:enable cyclomatic_complexity
}

// MARK: - View

struct AlbumDetailView: View {
    let browseId: String
    @State private var viewModel: AlbumDetailViewModel
    @State private var pendingRoute: DetailRoute?
    @State private var showMoreSheet = false
    @State private var backdropColors: [Color] = []
    @State private var descriptionExpanded = false

    @Environment(\.dismiss) private var dismiss

    init(browseId: String) {
        self.browseId = browseId
        _viewModel = State(initialValue: AlbumDetailViewModel(browseId: browseId))
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                DetailStateContainer(
                    isLoading: viewModel.isLoading,
                    error: viewModel.error,
                    data: viewModel.album,
                    noun: "album",
                    emptyIcon: "music.note"
                ) { album in
                    albumContent(for: album)
                        .environment(\.colorScheme, .dark)
                        .foregroundStyle(.white)
                }
            }
            .scrollDisabled(viewModel.isLoading || viewModel.error != nil || viewModel.album == nil)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 52).allowsHitTesting(false)
            }
            .background(albumBackdrop)
            .miniPlayerTracksScroll().scrollEdgeEffectHidden(true, for: .bottom)
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    VariableBlurView(maxBlurRadius: 8, direction: .blurredTopClearBottom)
                        .frame(height: geometry.safeAreaInsets.top + 12)
                        .offset(y: -geometry.safeAreaInsets.top - (geometry.safeAreaInsets.top + 12) * 0.05)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            albumTopBar
                .zIndex(1)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard viewModel.isLoading else { return }
            await viewModel.load()
        }
        .detailRouteSheet(item: $pendingRoute)
        .sheet(isPresented: $showMoreSheet) {
            if let album = viewModel.album {
                AlbumMoreSheet(
                    album: album,
                    isSaved: viewModel.isSaved,
                    onToggleSave: { Task { await viewModel.toggleSave() } }
                )
            }
        }
    }

    private static func shareURL(for album: AlbumDetailInfo) -> URL? {
        SpotifyCatalogID.shareURL(for: album.browseId)
            ?? URL(string: "https://music.youtube.com/browse/\(album.browseId)")
    }

    private var albumTopBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Back")

            Spacer()

            if let album = viewModel.album,
               let url = Self.shareURL(for: album) {
                HStack(spacing: 0) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Share album")
                    Button { showMoreSheet = true } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Album options")
                }
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var artworkPalette: DetailArtworkPalette {
        DetailArtworkPalette(seed: backdropColors.first ?? .gray, isDark: colorScheme == .dark, surface: .album)
    }

    private var albumBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: artworkPalette.top, location: 0),
                .init(color: artworkPalette.bottom, location: 0.75),
                .init(color: artworkPalette.bottom, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea(.container)
    }

    private var albumPlayColor: Color { artworkPalette.playInk }

    @ViewBuilder
    private func albumContent(for album: AlbumDetailInfo) -> some View {
        LazyVStack(spacing: 0) {
            header(for: album)
                .padding(.bottom, 8)

            if album.songs.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 40)
                    Text("No songs found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                songList(for: album)
            }

            if !album.videos.isEmpty {
                carousel(title: "Music Videos") {
                    ForEach(album.videos.prefix(12), id: \.videoId) { video in
                        videoCard(video)
                    }
                }
            }

            if !album.featuredPlaylists.isEmpty {
                carousel(title: "Featured On") {
                    ForEach(album.featuredPlaylists.prefix(12), id: \.id) { playlist in
                        playlistCard(playlist)
                    }
                }
            }

            if !album.relatedAlbums.isEmpty {
                carousel(title: "You Might Also Like") {
                    ForEach(album.relatedAlbums.prefix(12), id: \.browseId) { related in
                        albumCard(related)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func carousel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, 20)
                .padding(.top, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    content()
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func albumCard(_ album: AlbumItem) -> some View {
        NavigationLink(value: DetailRoute.album(browseId: album.browseId)) {
            VStack(alignment: .leading, spacing: 6) {
                SmartArtwork(
                    url: ArtworkURLs.highRes(album.thumbnailUrl),
                    subject: .album(
                        title: album.title,
                        artist: album.artists.map(\.name).joined(separator: ", ")
                    )
                )
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(album.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                Text(album.artists.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func playlistCard(_ playlist: PlaylistItem) -> some View {
        NavigationLink(value: DetailRoute.playlist(playlistId: playlist.id)) {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImageView(url: playlist.thumbnailUrl)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(playlist.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                if let author = playlist.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func videoCard(_ video: SongItem) -> some View {
        Button {
            PlaybackQueue.play([video], log: Log.albumDetail, context: "Music video")
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                SmartArtwork(
                    url: video.thumbnailUrl,
                    subject: .track(
                        title: video.title,
                        artist: video.artists.map(\.name).joined(separator: ", "),
                        album: video.album,
                        duration: video.duration
                    )
                )
                    .frame(width: 220, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(video.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)
                Text(video.artistNamesDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func header(for album: AlbumDetailInfo) -> some View {
        VStack(spacing: 12) {
            // Album artwork
            HeroArtworkView(
                url: album.thumbnailUrl,
                subject: .album(
                    title: album.title,
                    artist: album.artists.map(\.name).joined(separator: ", ")
                ),
                onImageLoaded: { image in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        backdropColors = [image.extractAlbumBackdropColor()]
                    }
                }
            )

            // Album title
            Text(album.title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Clickable artist names
            if !album.artists.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(album.artists.enumerated()), id: \.element) { i, artist in
                        if i > 0 {
                            Text(", ")
                                .foregroundColor(.secondary)
                        }
                        if let artistId = artist.id {
                            NavigationLink(value: DetailRoute.artist(browseId: artistId)) {
                                Text(artist.name)
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(artist.name)
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Metadata: year • song count • duration
            let metaParts = metaStrings(for: album)
            if !metaParts.isEmpty {
                Text(metaParts.joined(separator: " • "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Action buttons: shuffle, play, more (matches playlist header)
            PlaybackControlsView(
                accent: albumPlayColor,
                albumStyle: true,
                showsMore: true,
                onPlay: { playAll(album) },
                onShuffle: { shufflePlay(album) },
                onMore: { showMoreSheet = true }
            )

            if let description = album.descriptionText, !description.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(descriptionExpanded ? nil : 3)
                    Button(descriptionExpanded ? "LESS" : "MORE") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            descriptionExpanded.toggle()
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func songList(for album: AlbumDetailInfo) -> some View {
        // Rows are direct children of the outer LazyVStack so they build
        // lazily; a wrapping VStack forces the whole list eagerly.
        ForEach(Array(album.songs.enumerated()), id: \.element.videoId) { index, song in
            SongRowView(
                song: song,
                onTap: { playSong(song, in: album) },
                onNavigate: { pendingRoute = $0 },
                index: index + 1
            )
            .id(song.videoId)

            if index < album.songs.count - 1 {
                Divider()
                    .padding(.leading, 42)
            }
        }
    }

    // MARK: - Actions

    private func playAll(_ album: AlbumDetailInfo) {
        PlaybackQueue.play(album.songs, log: Log.albumDetail, context: "Playing from album \(album.title)")
    }

    private func shufflePlay(_ album: AlbumDetailInfo) {
        PlaybackQueue.playShuffled(album.songs, log: Log.albumDetail, context: "Shuffle playing from album \(album.title)")
    }

    private func playSong(_ song: SongItem, in album: AlbumDetailInfo) {
        PlaybackQueue.play(song, in: album.songs, log: Log.albumDetail, context: "Playing \(song.title)")
    }

    // MARK: - Helpers

    /// Builds metadata strings like "2024 • 12 songs • 45:30"
    private func metaStrings(for album: AlbumDetailInfo) -> [String] {
        var parts: [String] = []
        if let year = album.year { parts.append("\(year)") }
        if let genre = album.genre, !genre.isEmpty { parts.append(genre) }
        if album.songCount > 0 { parts.append("\(album.songCount) song\(album.songCount != 1 ? "s" : "")") }
        if album.duration > 0 { parts.append(album.duration.formattedDuration) }
        return parts
    }
}

// MARK: - Album More Sheet

/// Overflow menu matching PlaylistMoreSheet, with Save to Library as the
/// first row (mirrors album.bookmarked_at).
struct AlbumMoreSheet: View {
    let album: AlbumDetailInfo
    let isSaved: Bool
    var onToggleSave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetChrome {
            MenuCard {
                if let onToggleSave {
                    MenuRow(
                        icon: isSaved ? "bookmark.fill" : "bookmark",
                        title: isSaved ? "Saved" : "Save to Library",
                        subtitle: isSaved ? "Remove from your library" : "Add to your library"
                    ) {
                        onToggleSave()
                        dismiss()
                    }
                    Divider()
                }
                MenuRow(
                    icon: "list.bullet",
                    title: "Add to Queue",
                    subtitle: "Add to the end of the queue"
                ) {
                    addToQueue()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "square.and.arrow.down",
                    title: "Download",
                    subtitle: "Download all songs for offline playback"
                ) {
                    downloadAll()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "square.and.arrow.up",
                    title: "Share",
                    subtitle: "Share this album with others"
                ) {
                    share()
                    dismiss()
                }
            }
        }
    }

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(contentsOf: album.songs)
        np.persistQueueState()
    }

    private func downloadAll() {
        let songs = album.songs
        Task { await DownloadManager.shared.downloadAll(songs) }
    }

    private func share() {
        let url = SpotifyCatalogID.shareURL(for: album.browseId)
            ?? URL(string: "https://music.youtube.com/browse/\(album.browseId)")
        guard let url else { return }
        presentShareSheet(items: [url])
        dismiss()
    }
}
