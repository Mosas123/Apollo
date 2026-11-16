//
//  SongRowView.swift
//  Trop
//
// Created by 686udjie on 12/09/2026.
//

import SwiftUI

/// Trailing ⋮ button shared by every song row.
struct MoreButton: View {
    @Environment(SettingsStore.self) private var settings
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            Text("⋮")
                .font(.body.weight(.black))
                .foregroundStyle(settings.accentColor)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        })
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }
}

/// Unified song row: artwork + title + artists • duration + overflow menu.
/// Replaces AlbumSongRow, PlaylistSongRow, PodcastEpisodeRow, DownloadedSongRow
/// and the song branch of YouTubeListItemView.
struct SongRowView: View {
    let song: SongItem
    var artSize: CGFloat = DesignTokens.thumbSmall
    var artRadius: CGFloat = DesignTokens.thumbRadius
    var onTap: () -> Void
    var onNavigate: ((DetailRoute) -> Void)?
    /// When set, shows a track number instead of artwork (album track lists).
    var index: Int? = nil

    @State private var durations = DurationResolver()
    @State private var showSongMenu = false

    var body: some View {
        HStack(spacing: DesignTokens.rowSpacing) {
            if let index {
                Text("\(index)")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
            } else {
                AsyncImageView(url: song.thumbnailUrl)
                    .frame(width: artSize, height: artSize)
                    .clipShape(RoundedRectangle(cornerRadius: artRadius, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(index == nil ? .subheadline : .body)
                    .fontWeight(index == nil ? .medium : .regular)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(song.subtitleLine(duration: durations.effectiveDuration(known: song.duration)))
                    .font(index == nil ? .caption : .subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 2) {
                MoreButton {
                    showSongMenu = true
                }
            }
            .sheet(isPresented: $showSongMenu) {
                SongMenuSheet(
                    song: song,
                    onNavigate: { onNavigate?($0) }
                )
            }
        }
        .background(DownloadCellProgressView(song: song))
        .padding(.horizontal, DesignTokens.screenHPadding)
        .padding(.vertical, DesignTokens.rowVPadding)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu { songContextMenu }
        .task { await durations.resolve(videoId: song.videoId, knownDuration: song.duration) }
        .onReceive(NotificationCenter.default.publisher(for: .durationDidUpdate)) { notification in
            durations.handleUpdate(notification, videoId: song.videoId)
        }
    }

    @ViewBuilder
    private var songContextMenu: some View {
        Button {
            PlaybackQueue.play([song], log: Log.homeScreenView, context: "Song menu play")
        } label: {
            Label("Play", systemImage: "play")
        }

        Button {
            let np = NowPlaying.shared
            let index = min(np.queueIndex + 1, np.queueSongs.count)
            np.queueSongs.insert(song, at: index)
            np.repairQueueIndex()
            np.persistQueueState()
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            NowPlaying.shared.queueSongs.append(song)
            NowPlaying.shared.persistQueueState()
        } label: {
            Label("Play After", systemImage: "text.line.last.and.arrowtriangle.forward")
        }

        Button {
            Task { await LikeStore.shared.toggle(song: song) }
        } label: {
            Label(
                LikeStore.shared.isLiked(videoId: song.videoId) ? "Unfavorite" : "Favorite",
                systemImage: LikeStore.shared.isLiked(videoId: song.videoId) ? "heart.fill" : "heart"
            )
        }

        if let onNavigate, let artistId = song.artists.first(where: { $0.id != nil })?.id {
            Button {
                onNavigate(.artist(browseId: artistId))
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }

        if let onNavigate, let albumId = song.albumId, !albumId.isEmpty {
            Button {
                onNavigate(.album(browseId: albumId))
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }

        if MusicPlaybackIdentity.isYouTube(song.videoId) {
            Button {
                PlaybackQueue.startRadio(for: song)
            } label: {
                Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
            }
        }

        if let url = URL(string: song.webUrl) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }

        Button {
            Task { @MainActor in showSongMenu = true }
        } label: {
            Label("More…", systemImage: "ellipsis")
        }
    }
}

/// Full-cell progress background shown while a song is downloading.
struct DownloadCellProgressView: View {
    let song: SongItem
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        let state = downloadManager.state(for: song.videoId)
        return GeometryReader { geo in
            if case .downloading(let fraction) = state {
                Color.accentColor.opacity(0.25)
                    .frame(
                        width: geo.size.width * CGFloat(min(max(fraction, 0), 1)),
                        height: geo.size.height
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
    }
}
