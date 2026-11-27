//
//  LikeStore.swift
//  Apollo
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
        let videoId = song.videoId
        let target = !isLiked(videoId: videoId)

        var updated = liked
        updated[videoId] = target
        liked = updated

        do {
            if MusicPlaybackIdentity.isYouTube(videoId) {
                // Guests and offline sessions keep their likes on this device; only
                // mirror to YouTube Music when there is a real session.
                let syncRemote = await CookieStore().isLoggedIn()
                if target {
                    try await SyncBridge.mutations.likeSong(videoId: videoId, syncRemote: syncRemote)
                } else {
                    try await SyncBridge.mutations.unlikeSong(videoId: videoId, syncRemote: syncRemote)
                }
                if target, SettingsStore.shared.autoDownloadOnLike {
                    await DownloadManager.shared.download(song: song)
                }
            } else {
                // Radio, Audius and add-on tracks have no YouTube counterpart;
                // they live only in the device library.
                try await saveLocal(song: song, liked: target)
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
            NotificationCenter.default.post(name: Notification.Name("apollo.likeChanged"), object: nil)
        } catch {
            var reverted = liked
            reverted[videoId] = !target
            liked = reverted
            Log.sync.error("toggleLike failed for videoId=\(videoId) target=\(target) error: \(error) (\(error.localizedDescription))")
        }
    }

    /// Stores a like for a non-YouTube track (radio, Audius, add-ons) straight
    /// into the local library.
    private func saveLocal(song: SongItem, liked target: Bool) async throws {
        let artistName = song.artists.isEmpty
            ? song.artistNamesDisplay
            : song.artists.map(\.name).joined(separator: ", ")
        let existing = try await DatabaseService.shared.fetchOne(SongEntity.self, key: song.videoId)
        var entity = SongEntity.merging(
            existing: existing,
            id: song.videoId,
            title: song.title,
            artistName: artistName,
            albumName: song.album,
            duration: song.duration,
            thumbnailUrl: song.thumbnailUrl,
            liked: target
        )
        entity.liked = target
        if target, entity.inLibrary == nil {
            entity.inLibrary = Date()
        }
        try await DatabaseService.shared.save(entity)
    }
}
