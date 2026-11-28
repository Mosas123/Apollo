import SwiftUI
import GRDB

enum LibraryListKind: Equatable {
    case playlists
    case artists
    case albums
    case podcasts

    var title: String {
        switch self {
        case .playlists: return "Playlists"
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .podcasts: return "Podcasts"
        }
    }
}

/// Simple list destinations reached from the Library rows.
struct LibraryListScreen: View {
    let kind: LibraryListKind

    @Environment(SettingsStore.self) private var settings

    @State private var playlists: [PlaylistEntity] = []
    @State private var artists: [ArtistEntity] = []
    @State private var albums: [AlbumEntity] = []
    @State private var podcasts: [PodcastEntity] = []
    @State private var isLoading = true
    @State private var showCreateDialog = false
    @State private var playlistToDelete: PlaylistEntity?

    var body: some View {
        List {
            switch kind {
            case .playlists:
                Section {
                    NavigationLink(value: DetailRoute.autoPlaylist(.likedSongs)) {
                        row(icon: "heart.fill", title: "Liked Songs")
                    }
                    NavigationLink(value: DetailRoute.downloads) {
                        row(icon: "arrow.down.circle.fill", title: "Downloads")
                    }
                    NavigationLink(value: DetailRoute.autoPlaylist(.topSongs(limit: 100))) {
                        row(icon: "__PROTECT_APOLLOHY__.fill", title: "My Top 100")
                    }
                }

                Section {
                    ForEach(playlists, id: \.id) { playlist in
                        NavigationLink(value: DetailRoute.playlist(playlistId: playlist.id)) {
                            artworkRow(image: playlist.thumbnailUrl, title: playlist.name, subtitle: nil)
                        }
                        .swipeActions {
                            if playlist.isEditable {
                                Button(role: .destructive) {
                                    playlistToDelete = playlist
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

            case .artists:
                ForEach(artists, id: \.id) { artist in
                    NavigationLink(value: DetailRoute.artist(browseId: artist.id)) {
                        artworkRow(
                            image: artist.thumbnailUrl,
                            title: artist.name,
                            subtitle: nil,
                            circle: true,
                            subject: .artist(name: artist.name, spotifyID: artist.id)
                        )
                    }
                }

            case .albums:
                ForEach(albums, id: \.id) { album in
                    NavigationLink(value: DetailRoute.album(browseId: album.id)) {
                        artworkRow(
                            image: album.thumbnailUrl,
                            title: album.title,
                            subtitle: album.songCount > 0 ? AppStrings.songs(album.songCount) : nil,
                            subject: .album(title: album.title, artist: "")
                        )
                    }
                }

            case .podcasts:
                ForEach(podcasts, id: \.id) { podcast in
                    NavigationLink(value: DetailRoute.podcast(browseId: podcast.id)) {
                        artworkRow(
                            image: podcast.thumbnailUrl,
                            title: podcast.name,
                            subtitle: nil,
                            subject: .podcast(show: podcast.name)
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if kind == .playlists {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateDialog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create playlist")
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .overlay {
            if showCreateDialog {
                CreatePlaylistDialog(
                    isPresented: $showCreateDialog,
                    onCreated: { await load() }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCreateDialog)
        .task { await load() }
        .destructiveConfirm(
            "Delete Playlist",
            isPresented: .init(
                get: { playlistToDelete != nil },
                set: { if !$0 { playlistToDelete = nil } }
            ),
            message: Text(AppStrings.format("Delete “%@”?", playlistToDelete?.name ?? "")),
            confirmTitle: "Delete"
        ) {
            if let playlist = playlistToDelete {
                Task { await deletePlaylist(playlist) }
            }
        }
    }

    // MARK: - Rows

    private func row(icon: String, title: String) -> some View {
        Label {
            Text(LocalizedStringKey(title))
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(settings.accentColor)
        }
    }

    private func artworkRow(
        image: String?,
        title: String,
        subtitle: String?,
        circle: Bool = false,
        subject: ArtworkSubject? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Group {
                if circle {
                    SmartArtwork(url: image, subject: subject)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else {
                    SmartArtwork(url: image, subject: subject)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Data

    private func load() async {
        do {
            switch kind {
            case .playlists:
                playlists = try await DatabaseService.shared.fetchAll(
                    PlaylistEntity.self,
                    sql: "SELECT * FROM playlist WHERE bookmarked_at IS NOT NULL ORDER BY name"
                )
            case .artists:
                artists = try await DatabaseService.shared.fetchAll(
                    ArtistEntity.self,
                    sql: "SELECT * FROM artist WHERE bookmarked_at IS NOT NULL ORDER BY name"
                )
            case .albums:
                albums = try await DatabaseService.shared.fetchAllAlbums()
            case .podcasts:
                podcasts = try await DatabaseService.shared.fetchAllPodcasts()
            }
            isLoading = false
        } catch {
            Log.libraryView.error("Library list load failed: \(error)")
            isLoading = false
        }
    }

    private func deletePlaylist(_ playlist: PlaylistEntity) async {
        do {
            try await SyncBridge.mutations.deletePlaylist(playlistId: playlist.id)
            await load()
        } catch {
            Log.libraryView.error("Failed to delete playlist: \(error)")
        }
    }
}
