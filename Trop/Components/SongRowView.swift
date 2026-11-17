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
                    .font(index == nil ? .headline : .body)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(song.subtitleLine(duration: durations.effectiveDuration(known: song.duration)))
                    .font(.subheadline)
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
        SongContextMenuButtons(song: song)
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
    // Only this row observes the fast-changing 0–99% value, instead of every
    // row observing the whole manager.
    @StateObject private var progress: DownloadProgressBox

    @MainActor
    init(song: SongItem) {
        self.song = song
        _progress = StateObject(wrappedValue: DownloadManager.shared.progressBox(for: song.videoId))
    }

    var body: some View {
        GeometryReader { geo in
            if progress.fraction > 0 {
                Color.accentColor.opacity(0.25)
                    .frame(
                        width: geo.size.width * CGFloat(min(max(progress.fraction, 0), 1)),
                        height: geo.size.height
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: progress.fraction)
    }
}
