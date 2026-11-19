import SwiftUI

/// The songs the listener liked, kept in the local library — not YouTube's
/// auto-generated "Liked Songs" playlist view.
struct LibrarySongsView: View {
    @State private var songs: [SongEntity] = []
    @State private var isLoading = true

    private var items: [SongItem] {
        songs.map { SongItem(entity: $0) }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if songs.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Songs you like are saved here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        PlaybackControlsView(
                            showsShuffle: true,
                            showsMore: false,
                            onPlay: playAll,
                            onShuffle: shuffleAll
                        )
                        .padding(.vertical, 12)

                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            SongRowView(
                                song: SongItem(entity: song),
                                onTap: { play(index) }
                            )
                            if index < songs.count - 1 {
                                Divider()
                                    .padding(.leading, 68)
                            }
                        }
                    }
                }
                .miniPlayerTracksScroll().scrollEdgeEffectHidden(true, for: .bottom)
            }
        }
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("trop.likeChanged"))) { _ in
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("trop.libraryChanged"))) { _ in
            Task { await load() }
        }
    }

    private func load() async {
        do {
            songs = try await DatabaseService.shared.fetchAllLikedSongs(sort: .recentlyAdded)
        } catch {
            Log.libraryView.error("Failed to load library songs: \(error)")
        }
        isLoading = false
    }

    private func playAll() {
        guard !items.isEmpty else { return }
        PlaybackQueue.play(items, log: Log.libraryView, context: "Library songs")
    }

    private func shuffleAll() {
        guard !items.isEmpty else { return }
        PlaybackQueue.playShuffled(items, log: Log.libraryView, context: "Library songs shuffle")
    }

    private func play(_ index: Int) {
        guard items.indices.contains(index) else { return }
        PlaybackQueue.play(items[index], in: items, log: Log.libraryView, context: "Library song")
    }
}
