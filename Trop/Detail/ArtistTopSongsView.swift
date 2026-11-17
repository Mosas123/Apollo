import SwiftUI

/// Full "Top Songs" list for an artist, Apple Music style: cover, title,
/// "album · year" and a per-row menu.
struct ArtistTopSongsView: View {
    let songs: [SongItem]
    let artistName: String

    @State private var menuSong: SongItem?
    @State private var showMenu = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.videoId) { index, song in
                    row(song)
                        .id(song.videoId)
                    if index < songs.count - 1 {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Top Songs")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll().scrollEdgeEffectHidden(true, for: .bottom)
        .sheet(isPresented: $showMenu) {
            if let menuSong {
                SongMenuSheet(song: menuSong, onNavigate: { AppRouter.shared.open($0) })
            }
        }
    }

    private func row(_ song: SongItem) -> some View {
        HStack(spacing: 12) {
            AsyncImageView(url: song.thumbnailUrl)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle(for: song))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            MoreButton {
                menuSong = song
                showMenu = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            PlaybackQueue.play(song, in: songs, log: Log.artistDetail, context: "Top songs")
        }
    }

    private func subtitle(for song: SongItem) -> String {
        var parts: [String] = []
        if let album = song.album, !album.isEmpty { parts.append(album) }
        if let year = song.year { parts.append(String(year)) }
        if parts.isEmpty { parts.append(song.artistNamesDisplay) }
        return parts.joined(separator: " · ")
    }
}
