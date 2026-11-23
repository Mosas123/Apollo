import Foundation
import GRDB

/// V2 is a separate, empty user-owned library. Nothing in this store queries
/// YouTube, calls SyncBridge, mutates the legacy schema or requires a login.
enum TropLibraryV2Store {
    struct PlaylistSummary: Equatable, Sendable {
        let id: String
        let name: String
        let entryCount: Int
    }

    struct PlaylistEntry: Equatable, Sendable {
        let id: String
        let recordingID: String
        let position: Int
    }

    /// All kinds use Trop UUIDs as identity; a remote account is never needed.
    @discardableResult
    static func createItem(
        kind: TropLibraryV2Kind,
        title rawTitle: String,
        artistOrAuthor rawAuthor: String? = nil,
        durationSeconds: Int = 0,
        liked: Bool = false
    ) async throws -> String {
        let title = try TropLibraryV2IdentityPolicy.checkedTitle(rawTitle)
        let author = try TropLibraryV2IdentityPolicy.checkedOptionalText(rawAuthor)
        guard durationSeconds >= 0, (!liked || kind == .recording) else {
            throw TropLibraryV2ValidationError.unexpectedItemKind
        }
        let id = TropLibraryV2IdentityPolicy.newID()
        let now = Date()
        let likedAt: Date? = liked ? now : nil
        try await DatabaseService.shared.write { db in
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_item (
                        id, kind, title, artist_or_author, duration_seconds,
                        saved_at, liked_at, created_at, modified_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    id, kind.rawValue, title, author, durationSeconds,
                    now, likedAt, now, now
                ]
            )
        }
        return id
    }

    static func createPlaylist(named name: String) async throws -> String {
        try await createItem(kind: .playlist, title: name)
    }

    static func createLikedRecording(
        title: String,
        artist: String?,
        durationSeconds: Int = 0
    ) async throws -> String {
        try await createItem(
            kind: .recording, title: title, artistOrAuthor: artist,
            durationSeconds: durationSeconds, liked: true
        )
    }

    static func setLiked(recordingID: String, liked: Bool) async throws {
        let id = try TropLibraryV2IdentityPolicy.checkedID(recordingID)
        let now = Date()
        let likedAt: Date? = liked ? now : nil
        try await DatabaseService.shared.write { db in
            let kind = try String.fetchOne(
                db, sql: "SELECT kind FROM trop_v2_item WHERE id = ?", arguments: [id]
            )
            guard let kind else { throw TropLibraryV2ValidationError.missingItem }
            guard kind == TropLibraryV2Kind.recording.rawValue else {
                throw TropLibraryV2ValidationError.unexpectedItemKind
            }
            try db.execute(
                sql: """
                    UPDATE trop_v2_item SET liked_at = ?, modified_at = ?
                    WHERE id = ?
                    """,
                arguments: [likedAt, now, id]
            )
        }
    }

    /// Optional import provenance. A verified alias can point to a saved Trop
    /// item, but never becomes the item's identity or grants playback rights.
    static func linkAlias(
        toItemID rawID: String,
        kind: TropLibraryV2Kind,
        alias: TropLibraryV2SourceAlias
    ) async throws {
        let itemID = try TropLibraryV2IdentityPolicy.checkedID(rawID)
        let id = TropLibraryV2IdentityPolicy.newID()
        try await DatabaseService.shared.write { db in
            let storedKind = try String.fetchOne(
                db, sql: "SELECT kind FROM trop_v2_item WHERE id = ?",
                arguments: [itemID]
            )
            guard let storedKind else { throw TropLibraryV2ValidationError.missingItem }
            guard storedKind == kind.rawValue else {
                throw TropLibraryV2ValidationError.unexpectedItemKind
            }
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_source_alias (
                        id, item_id, kind, provider, source_scope, external_id
                    )
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    id, itemID, kind.rawValue, alias.provider,
                    alias.scope, alias.externalID
                ]
            )
        }
    }

    /// No UNIQUE(playlist_id, recording_id): the same recording may appear
    /// multiple times. UUID membership identity is ready for future sync.
    @discardableResult
    static func appendRecording(
        _ rawRecordingID: String,
        toPlaylist rawPlaylistID: String
    ) async throws -> String {
        let recordingID = try TropLibraryV2IdentityPolicy.checkedID(rawRecordingID)
        let playlistID = try TropLibraryV2IdentityPolicy.checkedID(rawPlaylistID)
        let entryID = TropLibraryV2IdentityPolicy.newID()
        let createdAt = Date()
        try await DatabaseService.shared.write { db in
            let playlistKind = try String.fetchOne(
                db, sql: "SELECT kind FROM trop_v2_item WHERE id = ?",
                arguments: [playlistID]
            )
            let recordingKind = try String.fetchOne(
                db, sql: "SELECT kind FROM trop_v2_item WHERE id = ?",
                arguments: [recordingID]
            )
            guard playlistKind != nil, recordingKind != nil else {
                throw TropLibraryV2ValidationError.missingItem
            }
            guard playlistKind == TropLibraryV2Kind.playlist.rawValue,
                  recordingKind == TropLibraryV2Kind.recording.rawValue else {
                throw TropLibraryV2ValidationError.unexpectedItemKind
            }
            let position = try Int.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(MAX(position), -1) + 1
                    FROM trop_v2_playlist_entry WHERE playlist_id = ?
                    """,
                arguments: [playlistID]
            ) ?? 0
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_playlist_entry (
                        id, playlist_id, recording_id, position, created_at
                    )
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [entryID, playlistID, recordingID, position, createdAt]
            )
        }
        return entryID
    }

    /// One local write transaction for the player/search Add to Playlist
    /// flow. Unlike the legacy menu, this never calls SyncBridge or YouTube.
    /// The recording has a Trop-owned UUID; the original source identity is
    /// only a scoped alias (including when the track came from an add-on).
    enum PlaylistDestination: Sendable {
        case existing(String)
        case create(String)
    }

    @discardableResult
    static func saveToPlaylist(
        _ candidate: TropLibraryV2PlaybackCandidate,
        destination: PlaylistDestination
    ) async throws -> String {
        let title = try TropLibraryV2IdentityPolicy.checkedTitle(candidate.title)
        let artist = try TropLibraryV2IdentityPolicy.checkedOptionalText(candidate.artist)
        guard candidate.durationSeconds >= 0 else {
            throw TropLibraryV2ValidationError.invalidIdentifier
        }
        let alias = try TropLibraryV2SourceAlias(
            provider: candidate.provider, externalID: candidate.externalID
        )
        let existingPlaylistID: String?
        let newPlaylistName: String?
        switch destination {
        case .existing(let id):
            existingPlaylistID = try TropLibraryV2IdentityPolicy.checkedID(id)
            newPlaylistName = nil
        case .create(let name):
            existingPlaylistID = nil
            newPlaylistName = try TropLibraryV2IdentityPolicy.checkedTitle(name)
        }
        let now = Date()
        return try await DatabaseService.shared.writeReturning { db in
            let playlistID: String
            if let existingPlaylistID {
                let kind = try String.fetchOne(
                    db, sql: "SELECT kind FROM trop_v2_item WHERE id = ?",
                    arguments: [existingPlaylistID]
                )
                guard kind == TropLibraryV2Kind.playlist.rawValue else {
                    throw TropLibraryV2ValidationError.missingItem
                }
                playlistID = existingPlaylistID
            } else {
                guard let newPlaylistName else {
                    throw TropLibraryV2ValidationError.invalidTitle
                }
                playlistID = TropLibraryV2IdentityPolicy.newID()
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_item (
                            id, kind, title, artist_or_author, duration_seconds,
                            saved_at, liked_at, created_at, modified_at
                        ) VALUES (?, 'playlist', ?, NULL, 0, ?, NULL, ?, ?)
                        """,
                    arguments: [playlistID, newPlaylistName, now, now, now]
                )
            }

            let recordingID: String
            if let existingID = try String.fetchOne(
                db,
                sql: """
                    SELECT item_id FROM trop_v2_source_alias
                    WHERE kind = 'recording' AND provider = ?
                      AND source_scope = ? AND external_id = ?
                    """,
                arguments: [alias.provider, alias.scope, alias.externalID]
            ) {
                recordingID = existingID
            } else {
                recordingID = TropLibraryV2IdentityPolicy.newID()
                let aliasID = TropLibraryV2IdentityPolicy.newID()
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_item (
                            id, kind, title, artist_or_author, duration_seconds,
                            saved_at, liked_at, created_at, modified_at
                        ) VALUES (?, 'recording', ?, ?, ?, ?, NULL, ?, ?)
                        """,
                    arguments: [
                        recordingID, title, artist, candidate.durationSeconds,
                        now, now, now
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_source_alias (
                            id, item_id, kind, provider, source_scope, external_id
                        ) VALUES (?, ?, 'recording', ?, ?, ?)
                        """,
                    arguments: [
                        aliasID, recordingID, alias.provider, alias.scope,
                        alias.externalID
                    ]
                )
            }

            // Entry UUID is different from the recording UUID; intentional
            // duplicates are supported, but the picker guards rapid taps.
            let entryID = TropLibraryV2IdentityPolicy.newID()
            let position = try Int.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(MAX(position), -1) + 1
                    FROM trop_v2_playlist_entry WHERE playlist_id = ?
                    """,
                arguments: [playlistID]
            ) ?? 0
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_playlist_entry (
                        id, playlist_id, recording_id, position, created_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [entryID, playlistID, recordingID, position, now]
            )
            return playlistID
        }
    }

    static func playlists() async throws -> [PlaylistSummary] {
        try await DatabaseService.shared.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT item.id, item.title, COUNT(entry.id) AS entry_count
                    FROM trop_v2_item AS item
                    LEFT JOIN trop_v2_playlist_entry AS entry
                      ON entry.playlist_id = item.id
                    WHERE item.kind = 'playlist'
                    GROUP BY item.id
                    ORDER BY item.created_at, item.id
                    """
            ).map { row in
                PlaylistSummary(
                    id: row["id"], name: row["title"], entryCount: row["entry_count"]
                )
            }
        }
    }

    static func playlistEntries(_ rawPlaylistID: String) async throws -> [PlaylistEntry] {
        let id = try TropLibraryV2IdentityPolicy.checkedID(rawPlaylistID)
        return try await DatabaseService.shared.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, recording_id, position
                    FROM trop_v2_playlist_entry
                    WHERE playlist_id = ?
                    ORDER BY position, created_at, id
                    """,
                arguments: [id]
            ).map { row in
                PlaylistEntry(
                    id: row["id"], recordingID: row["recording_id"],
                    position: row["position"]
                )
            }
        }
    }

    struct RecordingSummary: Equatable, Sendable {
        let id: String
        let title: String
        let artist: String?
        let durationSeconds: Int
        let isLiked: Bool
    }

    struct PlaylistTrack: Equatable, Sendable {
        let id: String
        let recordingID: String
        let title: String
        let artist: String?
        let durationSeconds: Int
        let position: Int
    }

    /// A single user-initiated local transaction. Import/provider IDs are
    /// only a scoped lookup alias; saving never calls the remote provider.
    /// Repeated taps reuse the same recording, preventing duplicate likes.
    @discardableResult
    static func savePlaybackRecording(
        title rawTitle: String,
        artist rawArtist: String?,
        durationSeconds: Int,
        provider: String,
        externalID: String,
        liked: Bool
    ) async throws -> String {
        let title = try TropLibraryV2IdentityPolicy.checkedTitle(rawTitle)
        let artist = try TropLibraryV2IdentityPolicy.checkedOptionalText(rawArtist)
        guard durationSeconds >= 0 else {
            throw TropLibraryV2ValidationError.invalidIdentifier
        }
        let alias = try TropLibraryV2SourceAlias(
            provider: provider, externalID: externalID
        )
        let newID = TropLibraryV2IdentityPolicy.newID()
        let aliasID = TropLibraryV2IdentityPolicy.newID()
        let now = Date()
        return try await DatabaseService.shared.writeReturning { db in
            if let existingID = try String.fetchOne(
                db,
                sql: """
                    SELECT item_id FROM trop_v2_source_alias
                    WHERE kind = 'recording' AND provider = ?
                      AND source_scope = ? AND external_id = ?
                    """,
                arguments: [alias.provider, alias.scope, alias.externalID]
            ) {
                if liked {
                    try db.execute(
                        sql: """
                            UPDATE trop_v2_item
                            SET liked_at = COALESCE(liked_at, ?),
                                saved_at = COALESCE(saved_at, ?),
                                modified_at = ?
                            WHERE id = ? AND kind = 'recording'
                            """,
                        arguments: [now, now, now, existingID]
                    )
                }
                return existingID
            }
            let likedAt: Date? = liked ? now : nil
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_item (
                        id, kind, title, artist_or_author, duration_seconds,
                        saved_at, liked_at, created_at, modified_at
                    ) VALUES (?, 'recording', ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [newID, title, artist, durationSeconds, now, likedAt, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_source_alias (
                        id, item_id, kind, provider, source_scope, external_id
                    ) VALUES (?, ?, 'recording', ?, ?, ?)
                    """,
                arguments: [aliasID, newID, alias.provider, alias.scope, alias.externalID]
            )
            return newID
        }
    }

    /// The user explicitly chose one provider result found using saved
    /// metadata. Recheck the CURRENT SQLite row before linking: search results
    /// could have become stale, another recording could own this provider ID,
    /// or an older provider choice could already be active. No song, like,
    /// playlist entry, download or source reference is removed.
    static func linkConfirmedAudioSource(
        toRecordingID rawID: String,
        track: MusicCatalogTrack,
        requiresLossless: Bool,
        userApprovedAlternate: Bool = false
    ) async throws {
        let id = try TropLibraryV2IdentityPolicy.checkedID(rawID)
        guard let sourceAlias = TropLibraryV2AudioMatchPolicy.alias(for: track) else {
            throw TropLibraryV2AudioLinkError.notVerified
        }
        let scope = userApprovedAlternate ? "user-approved-alt" : "global"
        let alias = try TropLibraryV2SourceAlias(
            provider: sourceAlias.provider, scope: scope,
            externalID: sourceAlias.externalID
        )
        let newAliasID = TropLibraryV2IdentityPolicy.newID()
        try await DatabaseService.shared.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT kind, title, artist_or_author, duration_seconds
                    FROM trop_v2_item WHERE id = ?
                    """,
                arguments: [id]
            ) else { throw TropLibraryV2ValidationError.missingItem }
            let kind: String = row["kind"]
            guard kind == TropLibraryV2Kind.recording.rawValue else {
                throw TropLibraryV2ValidationError.unexpectedItemKind
            }
            let title: String = row["title"]
            let artist: String? = row["artist_or_author"]
            let duration: Int = row["duration_seconds"]
            let classification = TropMatchCandidatePolicy.classify(
                title: title, artist: artist, durationSeconds: duration,
                track: track, requiresLossless: requiresLossless
            )
            guard classification == .exact
                    || (userApprovedAlternate && classification == .review)
            else { throw TropLibraryV2AudioLinkError.notVerified }

            // An audio ID may not point at two different Trop recordings
            // merely because one user approved it as an alternate.
            let currentOwner = try String.fetchOne(
                db,
                sql: """
                    SELECT item_id FROM trop_v2_source_alias
                    WHERE kind = 'recording' AND provider = ?
                      AND external_id = ?
                      AND source_scope IN ('global', 'user-approved-alt')
                    """,
                arguments: [alias.provider, alias.externalID]
            )
            if let currentOwner {
                guard currentOwner == id else {
                    throw TropLibraryV2AudioLinkError.usedByAnotherRecording
                }
                return // Already linked: no duplicate row or side effects.
            }

            // Keep multiple verified sources, without replacing old links.
            // Cap growth if an addon returns unstable opaque IDs.
            let other = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM trop_v2_source_alias
                    WHERE item_id = ? AND kind = 'recording'
                      AND provider IN ('audius', 'qobuz', 'jiosaavn', 'addon')
                    """,
                arguments: [id]
            ) ?? 0
            guard other < 12 else {
                throw TropLibraryV2AudioLinkError.existingSource
            }
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_source_alias (
                        id, item_id, kind, provider, source_scope, external_id
                    ) VALUES (?, ?, 'recording', ?, ?, ?)
                    """,
                arguments: [
                    newAliasID, id, alias.provider,
                    alias.scope, alias.externalID
                ]
            )
        }
    }

    static func recordings() async throws -> [RecordingSummary] {
        try await DatabaseService.shared.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, title, artist_or_author, duration_seconds,
                           (liked_at IS NOT NULL) AS is_liked
                    FROM trop_v2_item
                    WHERE kind = 'recording' AND saved_at IS NOT NULL
                    ORDER BY saved_at DESC, id
                    """
            ).map { row in
                RecordingSummary(
                    id: row["id"], title: row["title"],
                    artist: row["artist_or_author"],
                    durationSeconds: row["duration_seconds"],
                    isLiked: row["is_liked"]
                )
            }
        }
    }

    /// Metadata-only catalogue categories for the original Library navigation.
    /// Only Trop-owned, explicitly saved V2 items are returned. No legacy DB,
    /// remote catalogue, provider login, or mutation is involved.
    struct SavedCatalogItem: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let subtitle: String?
    }

    static func savedCatalogItems(
        kind: TropLibraryV2Kind
    ) async throws -> [SavedCatalogItem] {
        guard kind == .artist || kind == .album || kind == .podcast else {
            throw TropLibraryV2ValidationError.unexpectedItemKind
        }
        return try await DatabaseService.shared.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, title, artist_or_author
                    FROM trop_v2_item
                    WHERE kind = ? AND saved_at IS NOT NULL
                    ORDER BY title COLLATE NOCASE, id
                    """,
                arguments: [kind.rawValue]
            ).map { row in
                SavedCatalogItem(
                    id: row["id"],
                    title: row["title"],
                    subtitle: row["artist_or_author"]
                )
            }
        }
    }

    static func playlistTracks(_ rawPlaylistID: String) async throws -> [PlaylistTrack] {
        let id = try TropLibraryV2IdentityPolicy.checkedID(rawPlaylistID)
        return try await DatabaseService.shared.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT entry.id, entry.recording_id, entry.position,
                           recording.title, recording.artist_or_author,
                           recording.duration_seconds
                    FROM trop_v2_playlist_entry AS entry
                    JOIN trop_v2_item AS recording
                      ON recording.id = entry.recording_id
                    WHERE entry.playlist_id = ?
                    ORDER BY entry.position, entry.created_at, entry.id
                    """,
                arguments: [id]
            ).map { row in
                PlaylistTrack(
                    id: row["id"], recordingID: row["recording_id"],
                    title: row["title"], artist: row["artist_or_author"],
                    durationSeconds: row["duration_seconds"],
                    position: row["position"]
                )
            }
        }
    }


    /// Fetch only a saved recording's known source references. Read-only,
    /// never probes YouTube, guesses by title or alters library relationships.
    static func sourceAliases(forRecordingID rawRecordingID: String) async throws -> [TropLibraryV2SourceAlias] {
        let recordingID = try TropLibraryV2IdentityPolicy.checkedID(rawRecordingID)
        return try await DatabaseService.shared.read { db in
            let kind = try String.fetchOne(
                db, sql: "SELECT kind FROM trop_v2_item WHERE id = ?",
                arguments: [recordingID]
            )
            guard kind == TropLibraryV2Kind.recording.rawValue else {
                throw TropLibraryV2ValidationError.missingItem
            }
            return try Row.fetchAll(
                db,
                sql: """
                    SELECT provider, source_scope, external_id
                    FROM trop_v2_source_alias
                    WHERE item_id = ? AND kind = 'recording'
                    ORDER BY provider, source_scope, external_id
                    """,
                arguments: [recordingID]
            ).map { row in
                try TropLibraryV2SourceAlias(
                    provider: row["provider"], scope: row["source_scope"],
                    externalID: row["external_id"]
                )
            }
        }
    }

    /// The player heart needs an alias lookup rather than a legacy video ID
    /// primary key. Unliking never deletes the item or its playlist entries.
    static func setLikedForSource(
        provider: String,
        externalID: String,
        liked: Bool
    ) async throws {
        let alias = try TropLibraryV2SourceAlias(
            provider: provider, externalID: externalID
        )
        let now = Date()
        let likedAt: Date? = liked ? now : nil
        try await DatabaseService.shared.write { db in
            guard let itemID = try String.fetchOne(
                db,
                sql: """
                    SELECT item_id FROM trop_v2_source_alias
                    WHERE kind = 'recording' AND provider = ?
                      AND source_scope = ? AND external_id = ?
                    """,
                arguments: [alias.provider, alias.scope, alias.externalID]
            ) else {
                // A song never liked in V2 has nothing to unlike.
                if !liked { return }
                throw TropLibraryV2ValidationError.missingItem
            }
            try db.execute(
                sql: """
                    UPDATE trop_v2_item SET liked_at = ?, modified_at = ?
                    WHERE id = ? AND kind = 'recording'
                    """,
                arguments: [likedAt, now, itemID]
            )
        }
    }

    static func likedPlaybackIDs() async throws -> [String] {
        try await DatabaseService.shared.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT alias.provider, alias.external_id
                    FROM trop_v2_item AS item
                    JOIN trop_v2_source_alias AS alias ON alias.item_id = item.id
                    WHERE item.kind = 'recording' AND item.liked_at IS NOT NULL
                    ORDER BY item.modified_at DESC
                    """
            )
            return rows.map { row in
                let provider: String = row["provider"]
                let externalID: String = row["external_id"]
                return provider == "youtube"
                    ? externalID : "\(provider):\(externalID)"
            }
        }
    }

}
