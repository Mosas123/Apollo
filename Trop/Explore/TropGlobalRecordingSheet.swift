import SwiftUI

/// Metadata cards are not implicitly audio. A user can save their own Trop
/// recording, or explicitly ask Trop Match for a provider-scoped audio source.
struct TropGlobalRecordingSheet: View {
    let recording: TropGlobalRecording

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var isSearching = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        TropLibraryV2ArtworkView(
                            title: recording.title,
                            artist: recording.artist,
                            durationSeconds: 0
                        )
                        .frame(width: 90, height: 90)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recording.title).font(.headline)
                            Text(recording.artist).foregroundStyle(.secondary)
                            if let album = recording.album {
                                Text(album).font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        Task { await findAudioAndPlay() }
                    } label: {
                        Label("Find audio and play", systemImage: "play.fill")
                    }
                    .disabled(isSaving || isSearching)
                    Button {
                        Task { await saveRecording() }
                    } label: {
                        Label("Save to Library", systemImage: "plus.circle")
                    }
                    .disabled(isSaving || isSearching)
                } footer: {
                    Text(
                        "Metadata from " + recording.source
                            + ". Playback uses Trop Match and an available "
                            + "independent audio provider. Saving creates "
                            + "a Trop-owned library item."
                    )
                }

                if isSaving || isSearching {
                    Section {
                        HStack {
                            ProgressView()
                            Text(isSearching ? "Finding independent audio…" : "Saving…")
                        }
                    }
                }
                if let message {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Discover music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func saveRecording() async {
        guard !isSaving, !isSearching else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await TropLibraryV2Store.recordings()
            if saved.contains(where: {
                TextMatch.titlesMatch($0.title, recording.title)
                    && TextMatch.artistsMatch($0.artist ?? "", recording.artist)
            }) {
                message = "Already in your Trop library."
                return
            }
            _ = try await TropLibraryV2Store.createItem(
                kind: .recording,
                title: recording.title,
                artistOrAuthor: recording.artist
            )
            message = "Saved to your Trop library."
        } catch {
            message = "Could not save. Your library was not changed."
        }
    }

    @MainActor
    private func findAudioAndPlay() async {
        guard !isSearching, !isSaving else { return }
        isSearching = true
        defer { isSearching = false }
        // An ephemeral metadata summary is never inserted into Library V2,
        // and its ID is never interpreted as a YouTube playback identifier.
        let candidate = TropLibraryV2Store.RecordingSummary(
            id: recording.id, title: recording.title,
            artist: recording.artist, durationSeconds: 0,
            isLiked: false
        )
        let matches = await TropLibraryV2AudioDiscovery.inspect(
            for: candidate,
            requiresLossless: SettingsStore.shared.musicQualityMode.prefersLossless
        )
        guard !Task.isCancelled else { return }
        guard let audio = matches.exact.first else {
            message = matches.review.isEmpty
                ? "No verified audio available at your selected quality."
                : "Only alternative versions found. Use Search to review versions."
            return
        }
        PlaybackQueue.play(
            audio.asQueueSong(), in: [audio.asQueueSong()],
            log: Log.explore, context: "Trop global catalogue"
        )
        dismiss()
    }
}
