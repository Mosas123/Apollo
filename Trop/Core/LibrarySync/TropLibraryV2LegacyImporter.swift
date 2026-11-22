import Foundation
import GRDB

/// First-stage local import engine. It has deliberately NO automatic launch
/// hook or public Settings action: a validated, restorable user backup must
/// be integrated before exposing the irreversible import button.
///
/// Import runs in one GRDB write transaction, leaves every legacy table
/// unchanged and is safe to retry. V2 IDs are new UUIDs; YouTube IDs are
/// limited to source aliases. Existing V2 user edits are never overwritten.
enum TropLibraryV2LegacyImporter {
    enum ImportError: Error, Sendable {
        case temporaryDatabase
        case unresolvedLegacyMemberships(Int)
        case malformedLegacyData
        case brokenImportLedger
        case conflictingSourceAlias
        case conflictingLegacyRelation
    }

    struct Report: Equatable, Sendable {
        var createdItems = 0
        var reusedItems = 0
        var createdEntries = 0
        var existingEntries = 0
        var userRemovedEntries = 0
        var createdRelations = 0
    }

    /// Safe to call ONLY after a separate, verified Files backup + explicit
    /// confirmation. No UI invokes this method until those gates exist.
    static func importLegacySnapshot() async throws -> Report {
        guard DatabaseService.shared.usesPersistentStore else {
            throw ImportError.temporaryDatabase
        }

        // DatabasePool.write is transactional. Any failed validation rolls
        // back the entire import; the original legacy rows are read-only.
        return try await DatabaseService.shared.writeReturning { db in
            let orphanCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM playlist_song_map AS membership
                    LEFT JOIN playlist AS list ON list.id = membership.playlist_id
                    LEFT JOIN song AS track ON track.id = membership.song_id
                    WHERE list.id IS NULL
                       OR (list.bookmarked_at IS NOT NULL AND track.id IS NULL)
                    """
            ) ?? 0
            guard orphanCount == 0 else {
                throw ImportError.unresolvedLegacyMemberships(orphanCount)
            }

            let now = Date()
            var report = Report()

            // Each query explicitly allowlists non-sensitive columns. Never
            // SELECT *, access auth tokens, playback URLs or local file paths.
            try migrate(
                db, kind: .recording, now: now, report: &report,
                sql: """
                    SELECT id, title, artist_name AS author,
                           duration AS duration_seconds, liked, NULL AS related_id
                    FROM song
                    WHERE liked = 1
                       OR (in_library IS NOT NULL AND in_library <> '')
                       OR id IN (
                           SELECT map.song_id FROM playlist_song_map AS map
                           JOIN playlist AS list ON list.id = map.playlist_id
                           WHERE list.bookmarked_at IS NOT NULL
                       )
                    ORDER BY id
                    """
            )
            try migrate(
                db, kind: .playlist, now: now, report: &report,
                sql: """
                    SELECT id, name AS title, NULL AS author,
                           0 AS duration_seconds, 0 AS liked, browse_id AS related_id
                    FROM playlist WHERE bookmarked_at IS NOT NULL ORDER BY id
                    """
            )
            try migrate(
                db, kind: .album, now: now, report: &report,
                sql: """
                    SELECT id, title, NULL AS author,
                           0 AS duration_seconds, 0 AS liked,
                           playlist_id AS related_id
                    FROM album WHERE bookmarked_at IS NOT NULL ORDER BY id
                    """
            )
            try migrate(
                db, kind: .artist, now: now, report: &report,
                sql: """
                    SELECT id, name AS title, NULL AS author,
                           0 AS duration_seconds, 0 AS liked, NULL AS related_id
                    FROM artist WHERE bookmarked_at IS NOT NULL ORDER BY id
                    """
            )
            try migrate(
                db, kind: .podcast, now: now, report: &report,
                sql: """
                    SELECT id, name AS title, NULL AS author,
                           0 AS duration_seconds, 0 AS liked, NULL AS related_id
                    FROM podcast WHERE subscribed_at IS NOT NULL ORDER BY id
                    """
            )
            try migrate(
                db, kind: .episode, now: now, report: &report,
                sql: """
                    SELECT id, title, podcast_name AS author,
                           duration AS duration_seconds, 0 AS liked,
                           podcast_id AS related_id
                    FROM episode WHERE saved_at IS NOT NULL ORDER BY id
                    """
            )

            // Memberships are identified by legacy map.id, not by the
            // recording: V2 can preserve duplicates and stable ordering.
            let memberships = try Row.fetchAll(
                db,
                sql: """
                    SELECT map.id AS legacy_id, map.playlist_id, map.song_id,
                           map.position
                    FROM playlist_song_map AS map
                    JOIN playlist AS list ON list.id = map.playlist_id
                    JOIN song AS track ON track.id = map.song_id
                    WHERE list.bookmarked_at IS NOT NULL
                    ORDER BY map.playlist_id, map.position, map.id
                    """
            )
            for row in memberships {
                let legacyID: Int64 = row["legacy_id"]
                let originalPosition: Int = row["position"]
                guard legacyID > 0, originalPosition >= 0 else {
                    throw ImportError.malformedLegacyData
                }
                let rawPlaylist: String = row["playlist_id"]
                let rawRecording: String = row["song_id"]
                let playlistID = try importedItemID(
                    db, kind: .playlist, legacyID: rawPlaylist
                )
                let recordingID = try importedItemID(
                    db, kind: .recording, legacyID: rawRecording
                )

                if let previous = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT entry_id FROM trop_v2_legacy_import_entry
                        WHERE legacy_membership_id = ?
                        """,
                    arguments: [legacyID]
                ) {
                    let entryID: String? = previous["entry_id"]
                    if let entryID {
                        let matching = try String.fetchOne(
                            db,
                            sql: """
                                SELECT id FROM trop_v2_playlist_entry
                                WHERE id = ? AND playlist_id = ? AND recording_id = ?
                                """,
                            arguments: [entryID, playlistID, recordingID]
                        )
                        guard matching != nil else {
                            throw ImportError.brokenImportLedger
                        }
                        report.existingEntries += 1
                    } else {
                        // User deliberately deleted an imported V2 entry.
                        // Never resurrect it on a repeated import.
                        report.userRemovedEntries += 1
                    }
                    continue
                }

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
                        INSERT INTO trop_v2_playlist_entry
                            (id, playlist_id, recording_id, position, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [entryID, playlistID, recordingID, position, now]
                )
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_legacy_import_entry
                            (legacy_membership_id, entry_id, imported_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [legacyID, entryID, now]
                )
                report.createdEntries += 1
            }
            return report
        }
    }

    private static func migrate(
        _ db: Database,
        kind: TropLibraryV2Kind,
        now: Date,
        report: inout Report,
        sql: String
    ) throws {
        for row in try Row.fetchAll(db, sql: sql) {
            let rawID: String = row["id"]
            let rawTitle: String = row["title"]
            let rawAuthor: String? = row["author"]
            let duration: Int = row["duration_seconds"]
            let likedInteger: Int = row["liked"]
            guard duration >= 0, likedInteger == 0 || likedInteger == 1 else {
                throw ImportError.malformedLegacyData
            }
            let title = try TropLibraryV2IdentityPolicy.checkedTitle(rawTitle)
            let author = try TropLibraryV2IdentityPolicy.checkedOptionalText(rawAuthor)
            let alias = try TropLibraryV2SourceAlias(
                provider: "youtube", externalID: rawID
            )
            let itemID: String
            if let existing = try String.fetchOne(
                db,
                sql: """
                    SELECT item_id FROM trop_v2_source_alias
                    WHERE provider = ? AND source_scope = ? AND kind = ?
                      AND external_id = ?
                    """,
                arguments: [alias.provider, alias.scope, kind.rawValue, alias.externalID]
            ) {
                let existingKind = try String.fetchOne(
                    db,
                    sql: "SELECT kind FROM trop_v2_item WHERE id = ?",
                    arguments: [existing]
                )
                guard existingKind == kind.rawValue else {
                    throw ImportError.conflictingSourceAlias
                }
                itemID = existing
                report.reusedItems += 1
                // A re-import never undoes a user's later rename or unlike.
            } else {
                itemID = TropLibraryV2IdentityPolicy.newID()
                let likedAt: Date? = likedInteger == 1 ? now : nil
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_item
                            (id, kind, title, artist_or_author, duration_seconds,
                             saved_at, liked_at, created_at, modified_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        itemID, kind.rawValue, title, author, duration,
                        now, likedAt, now, now
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_source_alias
                            (id, item_id, kind, provider, source_scope, external_id)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        TropLibraryV2IdentityPolicy.newID(), itemID, kind.rawValue,
                        alias.provider, alias.scope, alias.externalID
                    ]
                )
                report.createdItems += 1
            }

            let relatedID: String? = row["related_id"]
            guard let relatedID, !relatedID.isEmpty else { continue }
            let checked = try TropLibraryV2SourceAlias(
                provider: "youtube", externalID: relatedID
            )
            if kind == .playlist {
                try preserveBrowseAlias(db, itemID: itemID, externalID: checked.externalID)
            } else if kind == .album || kind == .episode {
                let relationKind = kind == .album ? "album_playlist" : "episode_podcast"
                if let previous: String = try String.fetchOne(
                    db,
                    sql: """
                        SELECT external_id FROM trop_v2_legacy_relation
                        WHERE owner_item_id = ? AND link_kind = ?
                        """,
                    arguments: [itemID, relationKind]
                ) {
                    guard previous == checked.externalID else {
                        throw ImportError.conflictingLegacyRelation
                    }
                } else {
                    try db.execute(
                        sql: """
                            INSERT INTO trop_v2_legacy_relation
                                (id, owner_item_id, link_kind, external_id, created_at)
                            VALUES (?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            TropLibraryV2IdentityPolicy.newID(), itemID,
                            relationKind, checked.externalID, now
                        ]
                    )
                    report.createdRelations += 1
                }
            }
        }
    }

    private static func importedItemID(
        _ db: Database,
        kind: TropLibraryV2Kind,
        legacyID: String
    ) throws -> String {
        let alias = try TropLibraryV2SourceAlias(
            provider: "youtube", externalID: legacyID
        )
        guard let id = try String.fetchOne(
            db,
            sql: """
                SELECT item_id FROM trop_v2_source_alias
                WHERE kind = ? AND provider = ? AND source_scope = ?
                  AND external_id = ?
                """,
            arguments: [kind.rawValue, alias.provider, alias.scope, alias.externalID]
        ) else {
            throw ImportError.brokenImportLedger
        }
        return id
    }

    private static func preserveBrowseAlias(
        _ db: Database,
        itemID: String,
        externalID: String
    ) throws {
        if let previous: String = try String.fetchOne(
            db,
            sql: """
                SELECT item_id FROM trop_v2_source_alias
                WHERE kind = 'playlist' AND provider = 'youtube'
                  AND source_scope = 'browse' AND external_id = ?
                """,
            arguments: [externalID]
        ) {
            guard previous == itemID else {
                throw ImportError.conflictingSourceAlias
            }
        } else {
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_source_alias
                        (id, item_id, kind, provider, source_scope, external_id)
                    VALUES (?, ?, 'playlist', 'youtube', 'browse', ?)
                    """,
                arguments: [
                    TropLibraryV2IdentityPolicy.newID(), itemID, externalID
                ]
            )
        }
    }
}
