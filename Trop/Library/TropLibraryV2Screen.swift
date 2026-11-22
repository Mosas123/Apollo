import SwiftUI

/// Deliberate opt-in preview while the rest of Trop moves off the legacy
/// YouTube-keyed library. Every write here is local; cloud and imports remain
/// separate, explicit actions.
struct TropLibraryV2Screen: View {
    @State private var recordings: [TropLibraryV2Store.RecordingSummary] = []
    @State private var playlists: [TropLibraryV2Store.PlaylistSummary] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var feedback: String?

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
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title).lineLimit(1)
                if let artist = recording.artist {
                    Text(artist).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await setLiked(recording: recording, liked: !recording.isLiked) }
            } label: {
                Image(systemName: recording.isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(recording.isLiked ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(recording.isLiked ? "Unlike song" : "Like song")
        }
    }

    @MainActor
    private func refresh() async {
        do {
            async let saved = TropLibraryV2Store.recordings()
            async let lists = TropLibraryV2Store.playlists()
            recordings = try await saved
            playlists = try await lists
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
            await refresh()
        } catch {
            feedback = "Could not update this favorite locally."
        }
    }
}

private struct TropLibraryV2PlaylistScreen: View {
    let playlist: TropLibraryV2Store.PlaylistSummary

    @State private var tracks: [TropLibraryV2Store.PlaylistTrack] = []
    @State private var message: String?
    @State private var isAdding = false

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
                    HStack {
                        Text("\(track.position + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                            if let artist = track.artist {
                                Text(artist).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(playlist.name)
        .task { await refresh() }
        .refreshable { await refresh() }
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
