import SwiftUI

/// Routes to public metadata pages. These are never InnerTube browse IDs.
enum TropCatalogDetailRoute: Hashable {
    case artist(id: String, name: String)
    case album(id: String, title: String, artist: String)
}

struct TropCatalogArtistPage: View {
    let id: String
    let name: String

    @State private var recordings: [MusicBrainzRecording] = []
    @State private var albums: [MusicBrainzAlbum] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var artworkURL: String?
    @State private var playingID: String?
    @State private var playbackError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    ArtistAvatarImageView(
                        name: name, fallbackURL: artworkURL,
                        artistID: id
                    )
                    .frame(width: 156, height: 156)
                    .clipShape(Circle())
                    Text(name).font(.largeTitle.bold())
                }
                .padding(.horizontal, 16)

                if loading {
                    ProgressView("Loading artist catalogue…")
                        .padding(.horizontal, 16)
                }
                if !recordings.isEmpty {
                    Text("Songs")
                        .font(.title2.bold())
                        .padding(.horizontal, 16)
                    ForEach(recordings, id: \.id.storageKey) { item in
                        let recording = TropGlobalRecording(
                            id: item.id.storageKey, title: item.title,
                            artist: item.artist, album: nil, listenCount: 0,
                            source: "MusicBrainz", durationSeconds: item.durationSeconds
                        )
                        Button {
                            Task { await play(recording) }
                        } label: {
                            HStack(spacing: 12) {
                                TropLibraryV2ArtworkView(
                                    title: item.title, artist: item.artist,
                                    durationSeconds: item.durationSeconds ?? 0
                                )
                                .frame(width: 54, height: 54)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(item.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        .disabled(playingID != nil)
                        .contextMenu {
                            Button {
                                Task { await save(recording) }
                            } label: {
                                Label("Save to Library", systemImage: "plus")
                            }
                        }
                    }
                }

                if !albums.isEmpty {
                    Text("Albums and releases")
                        .font(.title2.bold())
                        .padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(albums, id: \.id.storageKey) { album in
                                NavigationLink {
                                    TropCatalogAlbumPage(
                                        id: album.id.mbid,
                                        title: album.title, artist: album.artist
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        TropCatalogAlbumCover(
                                            title: album.title, artist: album.artist
                                        )
                                        .frame(width: 140, height: 140)
                                        Text(album.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text(album.firstReleaseDate ?? album.artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 140, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                if !loading && recordings.isEmpty && albums.isEmpty {
                    ContentUnavailableView(
                        loadFailed ? "Catalogue unavailable" : "No releases found",
                        systemImage: "music.mic",
                        description: Text("Artist metadata could not be loaded right now.")
                    )
                }
            }
            .padding(.vertical, 20)
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task(id: id) { await load() }
        .alert("Audio unavailable", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
    }

    @MainActor
    private func load() async {
        loading = true
        loadFailed = false
        let catalog = MusicBrainzIdentityCatalog()
        async let songs = catalog.searchRecordingsByArtist(artist: name, limit: 30)
        async let releases = catalog.searchAlbumsByArtist(artist: name, limit: 24)
        let foundSongs = try? await songs
        let foundReleases = try? await releases
        guard !Task.isCancelled else { return }
        recordings = (foundSongs ?? []).filter {
            TextMatch.artistsMatch($0.artist, name)
        }
        albums = (foundReleases ?? []).filter {
            TextMatch.artistsMatch($0.artist, name)
        }
        loadFailed = foundSongs == nil && foundReleases == nil
        loading = false
    }

    @MainActor
    private func play(_ recording: TropGlobalRecording) async {
        guard playingID == nil else { return }
        playingID = recording.id
        defer { playingID = nil }
        do { try await TropGlobalPlaybackCoordinator.play(recording) }
        catch is CancellationError { return }
        catch { playbackError = error.localizedDescription }
    }

    @MainActor
    private func save(_ recording: TropGlobalRecording) async {
        do { try await TropGlobalPlaybackCoordinator.save(recording) }
        catch { playbackError = "Could not save this song." }
    }
}

struct TropCatalogAlbumPage: View {
    let id: String
    let title: String
    let artist: String

    @State private var tracks: [MusicBrainzAlbumTrack] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var playingID: String?
    @State private var playbackError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 16) {
                    TropCatalogAlbumCover(title: title, artist: artist)
                        .frame(width: 148, height: 148)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.title2.bold())
                        Text(artist).foregroundStyle(.secondary)
                        Text("Album").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                if loading {
                    ProgressView("Loading album tracks…")
                        .padding(.horizontal, 16)
                }
                if !tracks.isEmpty {
                    Text("Tracks")
                        .font(.title2.bold())
                        .padding(.horizontal, 16)
                    ForEach(Array(tracks.enumerated()), id: \.offset) { indexed in
                        let track = indexed.element
                        let recording = TropGlobalRecording(
                            id: "musicbrainz:recording:" + track.id,
                            title: track.title,
                            artist: track.artist.isEmpty ? artist : track.artist,
                            album: title, listenCount: 0, source: "MusicBrainz",
                            durationSeconds: track.durationSeconds
                        )
                        Button {
                            Task { await play(recording) }
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(track.position)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).foregroundStyle(.primary)
                                    Text(recording.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(playingID != nil)
                        .contextMenu {
                            Button {
                                Task { await save(recording) }
                            } label: {
                                Label("Save to Library", systemImage: "plus")
                            }
                        }
                    }
                } else if !loading {
                    ContentUnavailableView(
                        loadFailed ? "Album unavailable" : "Tracklist unavailable",
                        systemImage: "square.stack",
                        description: Text(
                            "MusicBrainz did not provide a verified release tracklist."
                        )
                    )
                }
            }
            .padding(.vertical, 20)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task(id: id) { await load() }
        .alert("Audio unavailable", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(playbackError ?? "") }
    }

    @MainActor
    private func load() async {
        loading = true
        loadFailed = false
        do {
            let fetched = try await MusicBrainzIdentityCatalog().albumTracks(
                releaseGroupID: id
            )
            guard !Task.isCancelled else { return }
            tracks = fetched
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
        }
        loading = false
    }

    @MainActor
    private func play(_ recording: TropGlobalRecording) async {
        guard playingID == nil else { return }
        playingID = recording.id
        defer { playingID = nil }
        do { try await TropGlobalPlaybackCoordinator.play(recording) }
        catch is CancellationError { return }
        catch { playbackError = error.localizedDescription }
    }

    @MainActor
    private func save(_ recording: TropGlobalRecording) async {
        do { try await TropGlobalPlaybackCoordinator.save(recording) }
        catch { playbackError = "Could not save this song." }
    }
}

/// Album art always belongs to a validated independent metadata provider.
struct TropCatalogAlbumCover: View {
    let title: String
    let artist: String
    @State private var imageURL: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .secondarySystemBackground))
            if let imageURL {
                AsyncImageView(url: imageURL)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "square.stack")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: artist + "|" + title) {
            imageURL = nil
            guard let url = await MetadataResolver.albumArtwork(
                title: title, artist: artist
            ), url.scheme?.lowercased() == "https" else { return }
            imageURL = url.absoluteString
        }
    }
}
