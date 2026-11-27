import Foundation

/// Only an action initiated inside Apollo can create outbound mutations.
/// File imports and remote refreshes must never echo back to the provider.
enum MusicChangeOrigin: String, Sendable {
    case user
    case fileImport
    case remoteRefresh
    case restoredBackup
}

enum MusicChange: Hashable, Sendable {
    case trackLiked(Bool)
    case trackSaved(Bool)
    case albumSaved(Bool)
    case artistSubscribed(Bool)
    case podcastSubscribed(Bool)
    case playlistTrackAdded(playlistID: String)
    case listenCompleted(sessionID: String, startedAt: Int64)

    var category: MusicSyncCategory {
        switch self {
        case .trackLiked: return .favorites
        case .trackSaved, .albumSaved, .artistSubscribed, .podcastSubscribed: return .library
        case .playlistTrackAdded: return .playlists
        case .listenCompleted: return .listens
        }
    }
}

enum MusicSyncCategory: String, Hashable, Sendable {
    case favorites, library, playlists, listens
}

enum MusicSyncDestination: String, Hashable, Sendable {
    case youtubeMusic, listenBrainz
}

enum MusicSyncStateAction: Hashable, Sendable {
    case trackLiked, trackSaved, albumSaved, artistSubscribed, podcastSubscribed
}

struct MusicSyncStateKey: Hashable, Sendable {
    let profileID: String
    let destination: MusicSyncDestination
    let accountID: String
    let canonicalItemID: String
    let action: MusicSyncStateAction
}

struct MusicSyncConnection: Sendable {
    let destination: MusicSyncDestination
    let profileID: String
    let accountID: String
    let enabledCategories: Set<MusicSyncCategory>
}

/// Account-owned YouTube IDs and owned playlist IDs must be verified by the
/// caller. Names and external provider IDs must not be guessed as YT IDs.
struct MusicSyncEvent: Sendable {
    let eventID: String
    let profileID: String
    let origin: MusicChangeOrigin
    let canonicalItemID: String
    let change: MusicChange
    let youtubeItemID: String?
    let verifiedOwnedPlaylistIDs: Set<String>
    let trackTitle: String?
    let artistName: String?
    let recordingMBID: String?
}

/// Contains no credentials. A later adapter validates account ownership,
/// API permissions and endpoint-specific parameters before sending it.
struct MusicSyncIntent: Hashable, Sendable {
    struct Key: Hashable, Sendable {
        let eventID: String
        let destination: MusicSyncDestination
        let accountID: String
    }

    let key: Key
    let profileID: String
    let canonicalItemID: String
    let change: MusicChange
    let destinationItemID: String?
    let trackTitle: String?
    let artistName: String?

    /// Repeated state changes to the same object coalesce *only while pending*.
    /// Completed listens remain distinct by session/event ID.
    var pendingStateKey: MusicSyncStateKey? {
        let action: MusicSyncStateAction
        switch change {
        case .trackLiked: action = .trackLiked
        case .trackSaved: action = .trackSaved
        case .albumSaved: action = .albumSaved
        case .artistSubscribed: action = .artistSubscribed
        case .podcastSubscribed: action = .podcastSubscribed
        case .playlistTrackAdded, .listenCompleted:
            // Never coalesce distinct playlist insertions or listens.
            return nil
        }
        return MusicSyncStateKey(
            profileID: profileID,
            destination: key.destination,
            accountID: key.accountID,
            canonicalItemID: canonicalItemID,
            action: action
        )
    }
}

struct MusicSyncPlan: Sendable {
    let intents: [MusicSyncIntent]
    let excludedUnmapped: Int
}

struct MusicSyncPlanner: Sendable {
    func plan(event: MusicSyncEvent, connections: [MusicSyncConnection]) -> MusicSyncPlan {
        guard event.origin == .user,
              !event.eventID.isEmpty, !event.profileID.isEmpty,
              !event.canonicalItemID.isEmpty else {
            return MusicSyncPlan(intents: [], excludedUnmapped: 0)
        }
        var intents: [MusicSyncIntent] = []
        var excluded = 0
        var seen = Set<MusicSyncIntent.Key>()
        for connection in connections {
            guard connection.profileID == event.profileID,
                  !connection.accountID.isEmpty,
                  connection.enabledCategories.contains(event.change.category) else { continue }
            let destinationID: String?
            switch connection.destination {
            case .youtubeMusic:
                guard let remoteID = event.youtubeItemID, !remoteID.isEmpty else {
                    excluded += 1
                    continue
                }
                if case .listenCompleted = event.change { continue }
                if case .playlistTrackAdded(let playlistID) = event.change,
                   !event.verifiedOwnedPlaylistIDs.contains(playlistID) {
                    excluded += 1
                    continue
                }
                destinationID = remoteID
            case .listenBrainz:
                switch event.change {
                case .listenCompleted:
                    guard !(event.trackTitle ?? "").isEmpty,
                          !(event.artistName ?? "").isEmpty else { excluded += 1; continue }
                case .trackLiked:
                    guard let mbid = event.recordingMBID, UUID(uuidString: mbid) != nil else {
                        excluded += 1
                        continue
                    }
                default: continue
                }
                destinationID = event.recordingMBID
            }
            let key = MusicSyncIntent.Key(
                eventID: event.eventID,
                destination: connection.destination,
                accountID: connection.accountID
            )
            guard seen.insert(key).inserted else { continue }
            intents.append(MusicSyncIntent(
                key: key,
                profileID: event.profileID,
                canonicalItemID: event.canonicalItemID,
                change: event.change,
                destinationItemID: destinationID,
                trackTitle: event.trackTitle,
                artistName: event.artistName
            ))
        }
        return MusicSyncPlan(intents: intents, excludedUnmapped: excluded)
    }
}

enum MusicSyncDeliveryState: Sendable {
    case pending, inFlight, delivered, uncertain
}

struct MusicSyncQueuedIntent: Sendable {
    let intent: MusicSyncIntent
    var state: MusicSyncDeliveryState
}

/// In-memory state machine to be persisted transactionally in a future PR.
/// A timeout on an outbound write MUST NOT auto-retry: the remote API might have
/// accepted it. Reconciliation is needed to avoid double submissions.
struct MusicSyncOutbox: Sendable {
    private(set) var entries: [MusicSyncQueuedIntent] = []
    private var seenKeys = Set<MusicSyncIntent.Key>()

    mutating func enqueue(_ intentions: [MusicSyncIntent]) {
        for intent in intentions {
            // Keep tombstones for superseded pending intents, so an old event
            // replay cannot undo a newer like/unlike or subscription change.
            guard seenKeys.insert(intent.key).inserted else { continue }
            if let stateKey = intent.pendingStateKey {
                entries.removeAll {
                    $0.state == .pending && $0.intent.pendingStateKey == stateKey
                }
            }
            entries.append(MusicSyncQueuedIntent(intent: intent, state: .pending))
        }
    }

    mutating func mark(_ key: MusicSyncIntent.Key, as state: MusicSyncDeliveryState) {
        guard let index = entries.firstIndex(where: { $0.intent.key == key }) else { return }
        entries[index].state = state
    }
}

struct MusicImportReceipt: Hashable, Sendable {
    enum Mode: String, Hashable, Sendable { case playlist, library, history }
    let profileID: String
    let mode: Mode
    let sha256: String
    /// Optional explicit stable source selection, not merely a file name.
    let sourceKey: String?
}

enum MusicImportReplayDecision: Equatable {
    case alreadyApplied
    case newImportNeedsPreview
    case updatedSourceNeedsPreview
}

struct MusicImportReplayGuard: Sendable {
    func assess(_ proposed: MusicImportReceipt, previouslyApplied: [MusicImportReceipt]) -> MusicImportReplayDecision {
        guard !proposed.profileID.isEmpty,
              proposed.sha256.count == 64,
              proposed.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            return .newImportNeedsPreview
        }
        let sameScope = previouslyApplied.filter { $0.profileID == proposed.profileID && $0.mode == proposed.mode }
        if sameScope.contains(where: {
            $0.sha256 == proposed.sha256 && $0.sourceKey == proposed.sourceKey
        }) {
            return .alreadyApplied
        }
        if let sourceKey = proposed.sourceKey, !sourceKey.isEmpty,
           sameScope.contains(where: { $0.sourceKey == sourceKey }) {
            return .updatedSourceNeedsPreview
        }
        return .newImportNeedsPreview
    }
}
