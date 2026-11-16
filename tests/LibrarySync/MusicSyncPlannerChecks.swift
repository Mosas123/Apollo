import Foundation

@main
struct MusicSyncPlannerChecks {
    static func main() {
        let planner = MusicSyncPlanner()
        let connections = [
            MusicSyncConnection(destination: .youtubeMusic, profileID: "p1", accountID: "google-A",
                                enabledCategories: [.favorites, .library, .playlists]),
            MusicSyncConnection(destination: .lastFM, profileID: "p1", accountID: "lastfm-A",
                                enabledCategories: [.favorites, .listens]),
            MusicSyncConnection(destination: .listenBrainz, profileID: "p1", accountID: "lb-A",
                                enabledCategories: [.favorites, .listens]),
            MusicSyncConnection(destination: .youtubeMusic, profileID: "p2", accountID: "google-B",
                                enabledCategories: [.favorites, .library])
        ]
        func event(_ id: String, _ origin: MusicChangeOrigin, _ change: MusicChange,
                   youtube: String? = "videoABC", mbid: String? = nil) -> MusicSyncEvent {
            MusicSyncEvent(eventID: id, profileID: "p1", origin: origin, canonicalItemID: "canonical-A",
                           change: change, youtubeItemID: youtube, verifiedOwnedPlaylistIDs: ["owner-playlist"],
                           trackTitle: "Track", artistName: "Artist", recordingMBID: mbid)
        }
        let like = planner.plan(event: event("like1", .user, .trackLiked(true)), connections: connections)
        precondition(like.intents.map { $0.key.destination } == [.youtubeMusic, .lastFM])
        precondition(like.excludedUnmapped == 1) // ListenBrainz requires recording MBID
        precondition(like.intents.allSatisfy { $0.profileID == "p1" })

        let noYoutube = planner.plan(event: event("like2", .user, .trackLiked(true), youtube: nil),
                                     connections: connections)
        precondition(noYoutube.intents.map { $0.key.destination } == [.lastFM])
        precondition(noYoutube.excludedUnmapped == 2)
        precondition(planner.plan(event: event("from-file", .fileImport, .trackLiked(true)),
                                  connections: connections).intents.isEmpty)
        precondition(planner.plan(event: event("remote", .remoteRefresh, .trackLiked(true)),
                                  connections: connections).intents.isEmpty)
        precondition(planner.plan(event: event("backup", .restoredBackup, .trackLiked(true)),
                                  connections: connections).intents.isEmpty)

        let podcast = planner.plan(event: event("pod", .user, .podcastSubscribed(true)), connections: connections)
        precondition(podcast.intents.count == 1)
        precondition(podcast.intents[0].key.destination == .youtubeMusic)
        let album = planner.plan(event: event("album", .user, .albumSaved(true)), connections: connections)
        precondition(album.intents.count == 1)
        let playlist = planner.plan(event: event("add", .user, .playlistTrackAdded(playlistID: "owner-playlist")),
                                    connections: connections)
        precondition(playlist.intents.count == 1)
        let notOwned = planner.plan(event: event("add2", .user, .playlistTrackAdded(playlistID: "not-owned")),
                                   connections: connections)
        precondition(notOwned.intents.isEmpty)
        let listened = planner.plan(event: event("listen-1", .user,
                                                 .listenCompleted(sessionID: "session-A", startedAt: 100)),
                                     connections: connections)
        precondition(listened.intents.count == 2)
        precondition(!listened.intents.contains { $0.key.destination == .youtubeMusic })
        let loved = planner.plan(event: event("liked-mbid", .user, .trackLiked(true),
                                                mbid: "7f2b9f43-e5cb-49f4-83fb-6830ac60bf61"),
                                 connections: connections)
        precondition(loved.intents.count == 3)

        var outbox = MusicSyncOutbox()
        outbox.enqueue(like.intents)
        outbox.enqueue(like.intents)
        precondition(outbox.entries.count == 2)
        let unlike = planner.plan(event: event("unlike", .user, .trackLiked(false)), connections: connections)
        outbox.enqueue(unlike.intents)
        precondition(outbox.entries.count == 2) // only latest pending state
        precondition(outbox.entries.allSatisfy { $0.intent.change == .trackLiked(false) })
        outbox.mark(outbox.entries[0].intent.key, as: .inFlight)
        outbox.enqueue(like.intents)
        precondition(outbox.entries.count == 2) // replay of superseded action cannot revert it
        let likeAgain = planner.plan(event: event("like3", .user, .trackLiked(true)),
                                     connections: connections)
        outbox.enqueue(likeAgain.intents)
        precondition(outbox.entries.count == 3) // keep in-flight mutation, queue new state
        outbox.enqueue(listened.intents)
        let add1 = planner.plan(event: event("playlist-1", .user,
                                               .playlistTrackAdded(playlistID: "owner-playlist")),
                                connections: connections)
        let add2 = planner.plan(event: event("playlist-2", .user,
                                               .playlistTrackAdded(playlistID: "owner-playlist")),
                                connections: connections)
        outbox.enqueue(add1.intents)
        outbox.enqueue(add2.intents)
        precondition(outbox.entries.filter {
            if case .playlistTrackAdded = $0.intent.change { return true }
            return false
        }.count == 2) // repeated playlist entries may be intentional
        let anotherListen = planner.plan(event: event("listen-2", .user,
                                                      .listenCompleted(sessionID: "session-B", startedAt: 100)),
                                         connections: connections)
        outbox.enqueue(anotherListen.intents)
        precondition(outbox.entries.filter {
            if case .listenCompleted = $0.intent.change { return true }
            return false
        }.count == 4) // different sessions are legitimate repeated plays
        outbox.mark(listened.intents[0].key, as: .uncertain)
        precondition(outbox.entries.first(where: { $0.intent.key == listened.intents[0].key })?.state == .uncertain)
        outbox.enqueue(listened.intents)
        precondition(outbox.entries.filter { $0.intent.key == listened.intents[0].key }.count == 1)

        let guarder = MusicImportReplayGuard()
        let shaA = String(repeating: "a", count: 64)
        let shaB = String(repeating: "b", count: 64)
        let first = MusicImportReceipt(profileID: "p1", mode: .playlist, sha256: shaA, sourceKey: "spotify:mix1")
        let repeated = MusicImportReceipt(profileID: "p1", mode: .playlist, sha256: shaA, sourceKey: "spotify:mix1")
        let differentPlaylist = MusicImportReceipt(profileID: "p1", mode: .playlist, sha256: shaA, sourceKey: "spotify:mix2")
        let changed = MusicImportReceipt(profileID: "p1", mode: .playlist, sha256: shaB, sourceKey: "spotify:mix1")
        let otherUser = MusicImportReceipt(profileID: "p2", mode: .playlist, sha256: shaA, sourceKey: nil)
        let favorites = MusicImportReceipt(profileID: "p1", mode: .library, sha256: shaA, sourceKey: nil)
        precondition(guarder.assess(first, previouslyApplied: []) == .newImportNeedsPreview)
        precondition(guarder.assess(repeated, previouslyApplied: [first]) == .alreadyApplied)
        precondition(guarder.assess(changed, previouslyApplied: [first]) == .updatedSourceNeedsPreview)
        precondition(guarder.assess(differentPlaylist, previouslyApplied: [first]) == .newImportNeedsPreview)
        precondition(guarder.assess(otherUser, previouslyApplied: [first]) == .newImportNeedsPreview)
        precondition(guarder.assess(favorites, previouslyApplied: [first]) == .newImportNeedsPreview)
        print("Music sync and import replay checks passed")
    }
}
