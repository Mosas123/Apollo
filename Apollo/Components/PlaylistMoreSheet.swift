//
//  PlaylistMoreSheet.swift
//  Apollo
//
//  Created by 686udjie on 28/08/2026.
//

import SwiftUI

struct PlaylistMoreSheet: View {
    let playlist: PlaylistDetailInfo
    var onSync: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showEditAlert = false
    @State private var isSaved = false

    private var isSpotify: Bool {
        SpotifyCatalogID.isSpotify(playlist.playlistId)
    }
    @State private var editedName = ""

    var body: some View {
        SheetChrome {
            MenuCard {
                if isSpotify {
                    MenuRow(
                        icon: isSaved ? "bookmark.fill" : "bookmark",
                        title: isSaved ? "Saved" : "Save to Library",
                        subtitle: isSaved ? "Remove from your library" : "Add to your library"
                    ) {
                        toggleSaved()
                        dismiss()
                    }
                    Divider()
                }
                if !isSpotify {
                    MenuRow(
                        icon: "pencil",
                        title: "Edit",
                        subtitle: "Edit playlist"
                    ) {
                        editedName = playlist.title
                        showEditAlert = true
                    }
                    Divider()
                    MenuRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Sync",
                        subtitle: "Sync this playlist with YouTube Music"
                    ) {
                        onSync?()
                        dismiss()
                    }
                    Divider()
                }
                MenuRow(
                    icon: "list.bullet",
                    title: "Add to Queue",
                    subtitle: "Add to the end of the queue"
                ) {
                    addToQueue()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "square.and.arrow.down",
                    title: "Download",
                    subtitle: "Download all songs for offline playback"
                ) {
                    downloadAll()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "square.and.arrow.up",
                    title: "Share",
                    subtitle: "Share this playlist with others"
                ) {
                    share()
                    dismiss()
                }
                if !isSpotify {
                    Divider()
                    MenuRow(
                        icon: "trash",
                        title: "Delete",
                        subtitle: "Remove all downloads",
                        destructive: true
                    ) {
                        deleteAllDownloads()
                        dismiss()
                    }
                }
            }
        }
        .task {
            guard isSpotify else { return }
            let saved = try? await DatabaseService.shared.fetchOne(
                PlaylistEntity.self,
                key: playlist.playlistId
            )
            isSaved = saved?.bookmarkedAt != nil
        }
        .textPrompt(
            "Rename Playlist",
            isPresented: $showEditAlert,
            placeholder: "Playlist name",
            text: $editedName,
            okTitle: "Rename",
            onOK: renamePlaylist
        )
    }

    // MARK: - Actions

    private func renamePlaylist() {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != playlist.title else { return }
        Task {
            try? await SyncBridge.mutations.renamePlaylist(
                playlistId: playlist.playlistId,
                newName: name
            )
        }
    }

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(contentsOf: playlist.songs)
        np.persistQueueState()
    }

    private func downloadAll() {
        let songs = playlist.songs
        Task { await DownloadManager.shared.downloadAll(songs) }
    }

    private func toggleSaved() {
        Task { @MainActor in
            let db = DatabaseService.shared
            do {
                if isSaved {
                    if let entity = try await db.fetchOne(
                        PlaylistEntity.self,
                        key: playlist.playlistId
                    ) {
                        try await db.delete(entity)
                    }
                } else {
                    try await db.save(
                        PlaylistEntity(
                            id: playlist.playlistId,
                            browseId: playlist.playlistId,
                            name: playlist.title,
                            thumbnailUrl: playlist.thumbnailUrl,
                            isEditable: false,
                            bookmarkedAt: Date(),
                            remoteSongCount: playlist.songCount
                        )
                    )
                }
                isSaved.toggle()
                NotificationCenter.default.post(
                    name: Notification.Name("apollo.libraryChanged"),
                    object: nil
                )
            } catch {
                Log.playlistDetail.error("Playlist save failed: \(error)")
            }
        }
    }

    private func share() {
        let url = SpotifyCatalogID.shareURL(for: playlist.playlistId)
            ?? URL.playlistShareURL(id: playlist.playlistId)
        guard let url else { return }
        presentShareSheet(items: [url])
        dismiss()
    }

    private func deleteAllDownloads() {
        let dm = DownloadManager.shared
        for song in playlist.songs {
            Task { await dm.delete(videoId: song.videoId) }
        }
    }
}
