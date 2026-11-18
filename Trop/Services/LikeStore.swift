//
//  LikeStore.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import Combine
import Foundation
import GRDB

@MainActor
class LikeStore: ObservableObject {
    static let shared = LikeStore()

    @Published private(set) var liked: [String: Bool] = [:]

    private init() {
        Task { await refresh() }
    }

    func isLiked(videoId: String) -> Bool {
        liked[videoId] ?? false
    }

    func refresh() async {
        let songs = (try? await DatabaseService.shared.fetchAllLikedSongs()) ?? []
        var dict: [String: Bool] = [:]
        for song in songs where song.liked {
            dict[song.id] = true
        }
        liked = dict
    }

    func toggle(song: SongItem) async {
        guard MusicPlaybackIdentity.isYouTube(song.videoId) else { return }
        let videoId = song.videoId
        let target = !isLiked(videoId: videoId)

        var updated = liked
        updated[videoId] = target
        liked = updated

        do {
            if target {
                try await SyncBridge.mutations.likeSong(videoId: videoId)
                if SettingsStore.shared.autoDownloadOnLike {
                    await DownloadManager.shared.download(song: song)
                }
            } else {
                try await SyncBridge.mutations.unlikeSong(videoId: videoId)
            }
            let primaryArtist = song.artists.first?.name ?? song.artistNamesDisplay
            if target {
                TasteProfileStore.shared.recordLike(artist: primaryArtist)
            } else {
                TasteProfileStore.shared.recordUnlike(artist: primaryArtist)
            }
            let artist = song.artists.map(\.name).joined(separator: ", ")
            let track = song.title
            if !artist.isEmpty, !track.isEmpty {
                Task { await LastFMIntegration.shared.handleLove(artist: artist, track: track, love: target) }
            }
            NotificationCenter.default.post(name: Notification.Name("trop.likeChanged"), object: nil)
        } catch {
            var reverted = liked
            reverted[videoId] = !target
            liked = reverted
            Log.sync.error("toggleLike failed for videoId=\(videoId) target=\(target) error: \(error) (\(error.localizedDescription))")
        }
    }
}
