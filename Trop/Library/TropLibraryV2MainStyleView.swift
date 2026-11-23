import SwiftUI

/// The original main-branch Library presentation, backed exclusively by
/// Trop's independent V2 records. Neither this view nor its destinations
/// use legacy YouTube-keyed library routes, account login or SyncBridge.
struct TropLibraryV2MainStyleView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var router = AppRouter.shared
    @State private var recordings: [TropLibraryV2Store.RecordingSummary] = []
    @State private var playlistCount = 0
    @State private var isLoading = true
    @State private var headerOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 60
    @State private var message: String?
    @State private var playbackMessage: String?
    @State private var isSaving = false
    @State private var isStartingPlayback = false

    private var gridColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }

    var body: some View {
        NavigationStack(path: $router.libraryPath) {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: headerHeight)
                        libraryRowList
                        recentlyAddedSection
                        libraryActions
                        if let message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        }
                    }
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.automatic)
                .miniPlayerTracksScroll(headerOffset: quantizedHeaderOffset)
                .scrollEdgeEffectHidden(true, for: .bottom)

                TabHeaderView(
                    title: "Library",
                    accountIsLoggedIn: false,
                    accountImageUrl: nil,
                    onAccount: { router.libraryPath.append(DetailRoute.settings) },
                    accountInitial: nil
                )
                .floatingTabHeader(scrollOffset: headerOffset, height: $headerHeight)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .detailRouteDestinations()
            .task { await refresh() }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name("trop.likeChanged")
                )
            ) { _ in
                Task { await refresh() }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name("trop.libraryChanged")
                )
            ) { _ in
                Task { await refresh() }
            }
            .refreshable { await refresh() }
            .alert("Audio unavailable", isPresented: Binding(
                get: { playbackMessage != nil },
                set: { if !$0 { playbackMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(playbackMessage ?? "The recording remains saved.")
            }
        }
    }

    private var quantizedHeaderOffset: Binding<CGFloat> {
        Binding(
            get: { headerOffset },
            set: { newValue in
                if abs(newValue - headerOffset) >= 8 {
                    headerOffset = newValue
                }
            }
        )
    }

    /// Keep the six original main-branch Library navigation destinations,
    /// but route them to local V2 views instead of the legacy source tables.
    private var libraryRowList: some View {
        VStack(spacing: 0) {
            libraryRow(icon: "music.note.list", title: "Playlists") {
                TropLibraryV2PlaylistCollectionView()
            }
            rowDivider
            libraryRow(icon: "music.mic", title: "Artists") {
                TropLibraryV2CatalogCollectionView(kind: .artist, title: "Artists")
            }
            rowDivider
            libraryRow(icon: "square.stack", title: "Albums") {
                TropLibraryV2CatalogCollectionView(kind: .album, title: "Albums")
            }
            rowDivider
            libraryRow(icon: "music.note", title: "Songs") {
                TropLibraryV2SongCollectionView(likedOnly: false)
            }
            rowDivider
            libraryRow(
                icon: "antenna.radiowaves.left.and.right",
                title: "Podcasts"
            ) {
                TropLibraryV2CatalogCollectionView(kind: .podcast, title: "Podcasts")
            }
            rowDivider
            libraryRow(icon: "arrow.down.circle", title: "Downloaded") {
                DownloadsView()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 44)
    }

    private func libraryRow<Destination: View>(
        icon: String, title: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(settings.accentColor)
                    .frame(width: 30)
                Text(LocalizedStringKey(title))
                    .font(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Rebuild display artwork from independent music catalogues. Saved V2
    /// identities and audio sources remain separate from these image lookups.
    private var recentlyAddedSection: some View {
        let recent = Array(recordings.prefix(8))
        return Group {
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recently Added")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 16)

                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(recent, id: \.id) { recording in
                            Button {
                                Task { await playSavedRecording(recording) }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    TropLibraryV2ArtworkView(
                                        title: recording.title,
                                        artist: recording.artist,
                                        durationSeconds: recording.durationSeconds
                                    )
                                    .aspectRatio(1, contentMode: .fit)
                                    Text(recording.title)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if let artist = recording.artist {
                                        Text(artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isStartingPlayback)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 22)
            }
        }
    }

    /// Preserve the V2-only actions absent from the legacy main screen.
    private var libraryActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Collection")
                .font(.title3.weight(.bold))
            NavigationLink {
                TropLibraryV2SongCollectionView(likedOnly: true)
            } label: {
                Label("Liked Songs", systemImage: "heart.fill")
            }
            NavigationLink {
                TropLibraryV2RadioCollectionView()
            } label: {
                Label("Saved Radio Stations", systemImage: "dot.radiowaves.left.and.right")
            }
            Button {
                Task { await saveCurrentSong() }
            } label: {
                Label(
                    isSaving ? "Saving…" : "Save Currently Playing Song",
                    systemImage: "plus.circle"
                )
            }
            .disabled(isSaving)
            Text("Saved locally in Trop. No music service login required.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(playlistCount) playlists · \(recordings.count) songs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    @MainActor
    private func refresh() async {
        do {
            async let saved = TropLibraryV2Store.recordings()
            async let lists = TropLibraryV2Store.playlists()
            let (songs, userPlaylists) = try await (saved, lists)
            recordings = songs
            playlistCount = userPlaylists.count
            message = nil
        } catch {
            message = "Could not read your local library. Nothing was deleted."
        }
        isLoading = false
    }

    @MainActor
    private func saveCurrentSong() async {
        guard let current = TropLibraryV2PlaybackCandidate.current() else {
            message = "Select a supported song in the player first."
            return
        }
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await current.save()
            await refresh()
        } catch {
            message = "Could not save this recording. Your library was not replaced."
        }
    }

    @MainActor
    private func playSavedRecording(
        _ recording: TropLibraryV2Store.RecordingSummary
    ) async {
        guard !isStartingPlayback else { return }
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        do {
            try await TropLibraryV2PlaybackRouter.playSaved(recording)
        } catch is CancellationError {
            return
        } catch let error as TropLibraryV2PlaybackSourceError {
            playbackMessage = error.localizedDescription
        } catch {
            playbackMessage = "Could not start this audio source. The song remains saved."
        }
    }
}

/// A local V2 playlist picker with the regular iOS navigation appearance.
private struct TropLibraryV2PlaylistCollectionView: View {
    @State private var playlists: [TropLibraryV2Store.PlaylistSummary] = []
    @State private var showCreate = false
    @State private var newName = ""
    @State private var isCreating = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button {
                    newName = ""
                    showCreate = true
                } label: {
                    Label("Create Playlist", systemImage: "plus")
                }
                .disabled(isCreating)
            }
            Section("Your Playlists") {
                if playlists.isEmpty {
                    Text("No playlists saved in Trop yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(playlists, id: \.id) { playlist in
                    NavigationLink {
                        TropLibraryV2PlaylistScreen(playlist: playlist)
                    } label: {
                        HStack {
                            Label(playlist.name, systemImage: "music.note.list")
                            Spacer()
                            Text("\(playlist.entryCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert("Create Playlist", isPresented: $showCreate) {
            TextField("Playlist name", text: $newName)
            Button("Create") { Task { await createPlaylist() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This playlist belongs to Trop, not YouTube or another service.")
        }
    }

    @MainActor
    private func refresh() async {
        do {
            playlists = try await TropLibraryV2Store.playlists()
            message = nil
        } catch {
            message = "Could not load your playlists."
        }
    }

    @MainActor
    private func createPlaylist() async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            try await TropLibraryV2Store.createPlaylist(named: newName)
            newName = ""
            await refresh()
            NotificationCenter.default.post(
                name: Notification.Name("trop.libraryChanged"), object: nil
            )
        } catch {
            message = "Enter a valid playlist name. Your existing lists were preserved."
        }
    }
}

/// Shows the same saved-song records as the original V2 preview, including
/// like/unlike and provider-scoped playback. No legacy Music ID is synthesized.
private struct TropLibraryV2SongCollectionView: View {
    let likedOnly: Bool
    @State private var recordings: [TropLibraryV2Store.RecordingSummary] = []
    @State private var playbackMessage: String?
    @State private var isStartingPlayback = false
    @State private var message: String?

    private var visible: [TropLibraryV2Store.RecordingSummary] {
        likedOnly ? recordings.filter(\.isLiked) : recordings
    }

    var body: some View {
        List {
            if visible.isEmpty {
                Text(
                    likedOnly
                        ? "No liked songs yet."
                        : "No songs saved in Trop yet."
                )
                .foregroundStyle(.secondary)
            }
            ForEach(visible, id: \.id) { recording in
                HStack(spacing: 12) {
                    Button {
                        Task { await play(recording) }
                    } label: {
                        HStack(spacing: 12) {
                            TropLibraryV2ArtworkView(
                                title: recording.title,
                                artist: recording.artist,
                                durationSeconds: recording.durationSeconds
                            )
                            .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recording.title).lineLimit(1)
                                if let artist = recording.artist {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isStartingPlayback)
                    Button {
                        Task { await setLiked(recording, liked: !recording.isLiked) }
                    } label: {
                        Image(
                            systemName: recording.isLiked ? "heart.fill" : "heart"
                        )
                        .foregroundStyle(recording.isLiked ? Color.red : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(
                        recording.isLiked ? "Unlike Song" : "Like Song"
                    )
                }
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(likedOnly ? "Liked Songs" : "Songs")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("trop.likeChanged")
            )
        ) { _ in Task { await refresh() } }
        .alert("Audio unavailable", isPresented: Binding(
            get: { playbackMessage != nil },
            set: { if !$0 { playbackMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackMessage ?? "Your song remains saved.")
        }
    }

    @MainActor
    private func refresh() async {
        do {
            recordings = try await TropLibraryV2Store.recordings()
            message = nil
        } catch {
            message = "Could not load saved songs."
        }
    }

    @MainActor
    private func play(_ recording: TropLibraryV2Store.RecordingSummary) async {
        guard !isStartingPlayback else { return }
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        do {
            try await TropLibraryV2PlaybackRouter.playSaved(recording)
        } catch is CancellationError {
            return
        } catch let error as TropLibraryV2PlaybackSourceError {
            playbackMessage = error.localizedDescription
        } catch {
            playbackMessage = "Could not start this source. The song remains saved."
        }
    }

    @MainActor
    private func setLiked(
        _ recording: TropLibraryV2Store.RecordingSummary, liked: Bool
    ) async {
        do {
            try await TropLibraryV2Store.setLiked(
                recordingID: recording.id, liked: liked
            )
            await LikeStore.shared.refresh()
            NotificationCenter.default.post(
                name: Notification.Name("trop.likeChanged"), object: nil
            )
            await refresh()
        } catch {
            message = "Could not change the favorite. Nothing was deleted."
        }
    }
}

/// Albums, artists and podcasts are read from Trop-owned V2 metadata. The
/// first V2 slice does not have a full detail browser or cover art for these.
private struct TropLibraryV2CatalogCollectionView: View {
    let kind: TropLibraryV2Kind
    let title: String
    @State private var items: [TropLibraryV2Store.SavedCatalogItem] = []
    @State private var message: String?

    var body: some View {
        List {
            if items.isEmpty {
                Text("No \(title.lowercased()) saved in Library V2 yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    @MainActor
    private func refresh() async {
        do {
            items = try await TropLibraryV2Store.savedCatalogItems(kind: kind)
            message = nil
        } catch {
            message = "Could not load saved \(title.lowercased())."
        }
    }
}

private struct TropLibraryV2RadioCollectionView: View {
    @State private var radios: [TropLibraryV2RadioStore.Favorite] = []
    @State private var message: String?

    var body: some View {
        List {
            if radios.isEmpty {
                Text("Save stations with the heart button in Radio.")
                    .foregroundStyle(.secondary)
            }
            ForEach(radios) { radio in
                Button {
                    Task { await play(radio.stationUUID) }
                } label: {
                    Label(
                        radio.name,
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Saved Radio Stations")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    @MainActor
    private func refresh() async {
        do {
            radios = try await TropLibraryV2RadioStore.favorites()
            message = nil
        } catch {
            message = "Could not load local radio favorites."
        }
    }

    @MainActor
    private func play(_ stationUUID: String) async {
        do {
            try await RadioPlaybackCoordinator.playSaved(
                stationUUID: stationUUID
            )
            message = nil
        } catch {
            message = "This radio station is unavailable. It remains saved."
        }
    }
}
