import SwiftUI

/// Deliberate opt-in preview while the rest of Trop moves off the legacy
/// YouTube-keyed library. Every write here is local; cloud and imports remain
/// separate, explicit actions.
struct TropLibraryV2Screen: View {
    @State private var recordings: [TropLibraryV2Store.RecordingSummary] = []
    @State private var playlists: [TropLibraryV2Store.PlaylistSummary] = []
    @State private var savedRadios: [TropLibraryV2RadioStore.Favorite] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var feedback: String?
    @State private var playbackMessage: String?
    @State private var isStartingPlayback = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Your library belongs to Trop", systemImage: "music.note.list")
                        .font(.headline)
                    Text("A fresh, private library on this device. No YouTube login or cloud connection required.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await saveCurrentSong() }
                    } label: {
                        Label("Save currently playing song", systemImage: "plus.circle")
                    }
                    .disabled(isSaving)
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Label("Downloaded audio", systemImage: "arrow.down.circle")
                    }
                }

                Section("Playlists") {
                    Button {
                        newPlaylistName = ""
                        showCreatePlaylist = true
                    } label: {
                        Label("Create playlist", systemImage: "plus")
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

                Section("Saved radio stations") {
                    if savedRadios.isEmpty {
                        Text("Save stations with the heart button in Radio.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(savedRadios) { radio in
                        Button {
                            Task { await playSavedRadio(radio.stationUUID) }
                        } label: {
                            Label(radio.name, systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                }

                Section("Liked songs") {
                    let liked = recordings.filter(\.isLiked)
                    if liked.isEmpty {
                        Text("No favorites yet. Save a song and tap its heart.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(liked, id: \.id) { recording in
                        songRow(recording)
                    }
                }

                Section("Saved songs") {
                    if recordings.isEmpty {
                        ContentUnavailableView(
                            "Your library is empty",
                            systemImage: "music.note",
                            description: Text("Play a song and choose Save to keep it in Trop.")
                        )
                    } else {
                        ForEach(recordings, id: \.id) { recording in
                            songRow(recording)
                        }
                    }
                }

                if let feedback {
                    Section {
                        Text(feedback).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .alert("Audio unavailable", isPresented: Binding(
                get: { playbackMessage != nil },
                set: { if !$0 { playbackMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(playbackMessage ?? "This song remains saved.")
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
            .onReceive(
                NotificationCenter.default.publisher(for: Notification.Name("trop.likeChanged"))
            ) { _ in
                Task { await refresh() }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: Notification.Name("trop.radioFavoritesChanged"))
            ) { _ in
                Task { await refresh() }
            }
            .alert("Create playlist", isPresented: $showCreatePlaylist) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Create") {
                    Task { await createPlaylist() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This playlist stays on your device until you choose to back it up or sync it.")
            }
        }
    }

    private func songRow(_ recording: TropLibraryV2Store.RecordingSummary) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await playSavedRecording(recording) }
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
                            Text(artist).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "play.fill").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isStartingPlayback)
            .accessibilityLabel("Play \(recording.title)")
            Button {
                Task { await setLiked(recording: recording, liked: !recording.isLiked) }
            } label: {
                Image(systemName: recording.isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(recording.isLiked ? Color.red : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(recording.isLiked ? "Unlike song" : "Like song")
        }
    }

    @MainActor
    private func playSavedRecording(_ recording: TropLibraryV2Store.RecordingSummary) async {
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
            playbackMessage = "Could not start this source. The saved song was not changed."
        }
    }

    @MainActor
    private func refresh() async {
        do {
            async let saved = TropLibraryV2Store.recordings()
            async let lists = TropLibraryV2Store.playlists()
            async let radios = TropLibraryV2RadioStore.favorites()
            recordings = try await saved
            playlists = try await lists
            savedRadios = try await radios
            feedback = nil
        } catch {
            feedback = "Could not read the local library. Nothing was deleted."
        }
        isLoading = false
    }

    @MainActor
    private func saveCurrentSong() async {
        guard let current = TropLibraryV2PlaybackCandidate.current() else {
            feedback = "Select a supported song in the player first."
            return
        }
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await current.save()
            await refresh()
        } catch {
            feedback = "This recording could not be saved. Your library was not replaced."
        }
    }

    @MainActor
    private func playSavedRadio(_ stationUUID: String) async {
        do {
            try await RadioPlaybackCoordinator.playSaved(stationUUID: stationUUID)
            feedback = nil
        } catch {
            feedback = "This station is unavailable right now. It remains saved."
        }
    }

    @MainActor
    private func createPlaylist() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await TropLibraryV2Store.createPlaylist(named: newPlaylistName)
            newPlaylistName = ""
            await refresh()
        } catch {
            feedback = "Enter a valid playlist name. No remote account is required."
        }
    }

    @MainActor
    private func setLiked(
        recording: TropLibraryV2Store.RecordingSummary,
        liked: Bool
    ) async {
        do {
            try await TropLibraryV2Store.setLiked(recordingID: recording.id, liked: liked)
            await LikeStore.shared.refresh()
            NotificationCenter.default.post(
                name: Notification.Name("trop.likeChanged"), object: nil
            )
            await refresh()
        } catch {
            feedback = "Could not update this favorite locally."
        }
    }
}

// Shared by Library V2 and its independent Home; keep the view internal.
struct TropLibraryV2PlaylistScreen: View {
    let playlist: TropLibraryV2Store.PlaylistSummary

    @State private var tracks: [TropLibraryV2Store.PlaylistTrack] = []
    @State private var message: String?
    @State private var isAdding = false
    @State private var isStartingPlayback = false
    @State private var playbackMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    Task { await appendCurrentSong() }
                } label: {
                    Label("Add currently playing song", systemImage: "plus.circle")
                }
                .disabled(isAdding)
                Text("Songs can appear more than once. This playlist belongs to Trop, not a streaming provider.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Songs") {
                if tracks.isEmpty {
                    Text("This playlist is empty.")
                        .foregroundStyle(.secondary)
                }
                ForEach(tracks, id: \.id) { track in
                    Button {
                        Task { await playPlaylist(startingAt: track.id) }
                    } label: {
                        HStack {
                            Text("\(track.position + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            TropLibraryV2ArtworkView(
                                title: track.title,
                                artist: track.artist,
                                durationSeconds: track.durationSeconds
                            )
                            .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                if let artist = track.artist {
                                    Text(artist).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "play.fill").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isStartingPlayback)
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(playlist.name)
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert("Audio unavailable", isPresented: Binding(
            get: { playbackMessage != nil },
            set: { if !$0 { playbackMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackMessage ?? "Your playlist remains saved.")
        }
    }

    @MainActor
    private func refresh() async {
        do {
            tracks = try await TropLibraryV2Store.playlistTracks(playlist.id)
            message = nil
        } catch {
            message = "Could not load the playlist."
        }
    }

    @MainActor
    private func playPlaylist(startingAt entryID: String) async {
        guard !isStartingPlayback,
              let index = tracks.firstIndex(where: { $0.id == entryID }) else {
            return
        }
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        do {
            try await TropLibraryV2PlaybackRouter.playPlaylist(tracks, startingAt: index)
        } catch is CancellationError {
            return
        } catch let error as TropLibraryV2PlaybackSourceError {
            playbackMessage = error.localizedDescription
        } catch {
            playbackMessage = "Could not start this playlist. All its songs remain saved."
        }
    }

    @MainActor
    private func appendCurrentSong() async {
        guard let current = TropLibraryV2PlaybackCandidate.current() else {
            message = "Select a supported song in the player first."
            return
        }
        guard !isAdding else { return }
        isAdding = true
        defer { isAdding = false }
        do {
            let id = try await current.save()
            try await TropLibraryV2Store.appendRecording(id, toPlaylist: playlist.id)
            await refresh()
        } catch {
            message = "Could not add this song to the playlist."
        }
    }
}
