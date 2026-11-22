import Foundation
import GRDB

/// Read-only forecast for the real legacy -> V2 importer. It never creates a
/// Trop UUID, writes a ledger, requests YouTube, or mutates a user's library.
/// Numbers describe the database at the instant of this one GRDB read; they
/// are NOT authorization to import without a verified recoverable backup.
enum TropLibraryV2MigrationDryRun {
    struct Report: Equatable, Sendable {
        var newItems = 0
        var reusedItems = 0
        var newEntries = 0
        var existingEntries = 0
        var userRemovedEntries = 0
        var unresolvedMemberships = 0
        var invalidItems = 0
        var conflictingAliases = 0
        var conflictingRelations = 0
        var brokenLedgerEntries = 0

        var hasBlockers: Bool {
            unresolvedMemberships > 0 || invalidItems > 0
                || conflictingAliases > 0 || conflictingRelations > 0
                || brokenLedgerEntries > 0
        }
    }

    private struct SourceKey: Hashable {
        let kind: TropLibraryV2Kind
        let legacyID: String
    }

    private struct ResolvedCandidate {
        let itemID: String?
    }

    /// The selection predicates intentionally mirror the current importer.
    /// Changes to legacy selection require updating both and the GRDB test.
    private static let selections: [(TropLibraryV2Kind, String)] = [
        (.recording, """
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
            """),
        (.playlist, """
            SELECT id, name AS title, NULL AS author,
                   0 AS duration_seconds, 0 AS liked, browse_id AS related_id
            FROM playlist WHERE bookmarked_at IS NOT NULL ORDER BY id
            """),
        (.album, """
            SELECT id, title, NULL AS author,
                   0 AS duration_seconds, 0 AS liked,
                   playlist_id AS related_id
            FROM album WHERE bookmarked_at IS NOT NULL ORDER BY id
            """),
        (.artist, """
            SELECT id, name AS title, NULL AS author,
                   0 AS duration_seconds, 0 AS liked, NULL AS related_id
            FROM artist WHERE bookmarked_at IS NOT NULL ORDER BY id
            """),
        (.podcast, """
            SELECT id, name AS title, NULL AS author,
                   0 AS duration_seconds, 0 AS liked, NULL AS related_id
            FROM podcast WHERE subscribed_at IS NOT NULL ORDER BY id
            """),
        (.episode, """
            SELECT id, title, podcast_name AS author,
                   duration AS duration_seconds, 0 AS liked,
                   podcast_id AS related_id
            FROM episode WHERE saved_at IS NOT NULL ORDER BY id
            """)
    ]

    static func load() async throws -> Report {
        guard DatabaseService.shared.usesPersistentStore else {
            throw TropLibraryV2LegacyImporter.ImportError.temporaryDatabase
        }
        return try await DatabaseService.shared.read { db in
            try scan(in: db)
        }
    }

    /// Internal hook for the disposable GRDB fixture; still read-only.
    static func scan(in db: Database) throws -> Report {
        var report = Report()
        report.unresolvedMemberships = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM playlist_song_map AS membership
            LEFT JOIN playlist AS list ON list.id = membership.playlist_id
            LEFT JOIN song AS track ON track.id = membership.song_id
            WHERE list.id IS NULL
               OR (list.bookmarked_at IS NOT NULL AND track.id IS NULL)
            """) ?? 0

        var candidates: [SourceKey: ResolvedCandidate] = [:]
        // A new, unsaved playlist alias cannot already have an owner. If two
        // different new playlists claim the same browse ID, fail closed.
        var newBrowseAliases: Set<String> = []

        for (kind, query) in selections {
            for row in try Row.fetchAll(db, sql: query) {
                let rawID: String = row["id"]
                let title: String = row["title"]
                let author: String? = row["author"]
                let duration: Int = row["duration_seconds"]
                let liked: Int = row["liked"]
                let relatedID: String? = row["related_id"]
                let alias: TropLibraryV2SourceAlias
                do {
                    guard duration >= 0, liked == 0 || liked == 1 else {
                        report.invalidItems += 1
                        continue
                    }
                    _ = try TropLibraryV2IdentityPolicy.checkedTitle(title)
                    _ = try TropLibraryV2IdentityPolicy.checkedOptionalText(author)
                    alias = try TropLibraryV2SourceAlias(
                        provider: "youtube", externalID: rawID
                    )
                } catch {
                    report.invalidItems += 1
                    continue
                }

                let existing = try String.fetchOne(db, sql: """
                    SELECT item_id FROM trop_v2_source_alias
                    WHERE provider = ? AND source_scope = ? AND kind = ?
                      AND external_id = ?
                    """, arguments: [
                        alias.provider, alias.scope, kind.rawValue, alias.externalID
                    ])
                if let existing {
                    let existingKind = try String.fetchOne(
                        db, sql: "SELECT kind FROM trop_v2_item WHERE id = ?",
                        arguments: [existing]
                    )
                    guard existingKind == kind.rawValue else {
                        report.conflictingAliases += 1
                        continue
                    }
                    report.reusedItems += 1
                } else {
                    report.newItems += 1
                }
                candidates[SourceKey(kind: kind, legacyID: rawID)] = .init(
                    itemID: existing
                )

                guard let relatedID, !relatedID.isEmpty else { continue }
                let checked: TropLibraryV2SourceAlias
                do {
                    checked = try TropLibraryV2SourceAlias(
                        provider: "youtube", externalID: relatedID
                    )
                } catch {
                    report.invalidItems += 1
                    continue
                }
                if kind == .playlist {
                    let owner = try String.fetchOne(db, sql: """
                        SELECT item_id FROM trop_v2_source_alias
                        WHERE kind = 'playlist' AND provider = 'youtube'
                          AND source_scope = 'browse' AND external_id = ?
                        """, arguments: [checked.externalID])
                    if let owner {
                        if owner != existing { report.conflictingAliases += 1 }
                    } else if existing == nil,
                              !newBrowseAliases.insert(checked.externalID).inserted {
                        report.conflictingAliases += 1
                    }
                } else if kind == .album || kind == .episode, let existing {
                    let relationKind = kind == .album ? "album_playlist" : "episode_podcast"
                    let previous = try String.fetchOne(db, sql: """
                        SELECT external_id FROM trop_v2_legacy_relation
                        WHERE owner_item_id = ? AND link_kind = ?
                        """, arguments: [existing, relationKind])
                    if let previous, previous != checked.externalID {
                        report.conflictingRelations += 1
                    }
                }
            }
        }

        let members = try Row.fetchAll(db, sql: """
            SELECT map.id AS legacy_id, map.playlist_id, map.song_id,
                   map.position
            FROM playlist_song_map AS map
            JOIN playlist AS list ON list.id = map.playlist_id
            JOIN song AS track ON track.id = map.song_id
            WHERE list.bookmarked_at IS NOT NULL
            ORDER BY map.playlist_id, map.position, map.id
            """)
        for row in members {
            let sourceID: Int64 = row["legacy_id"]
            let position: Int = row["position"]
            let playlistSource: String = row["playlist_id"]
            let recordingSource: String = row["song_id"]
            guard sourceID > 0, position >= 0 else {
                report.invalidItems += 1
                continue
            }
            guard let targetPlaylist = candidates[
                SourceKey(kind: .playlist, legacyID: playlistSource)
            ], let targetRecording = candidates[
                SourceKey(kind: .recording, legacyID: recordingSource)
            ] else {
                report.brokenLedgerEntries += 1
                continue
            }
            if let ledger = try Row.fetchOne(db, sql: """
                SELECT entry_id FROM trop_v2_legacy_import_entry
                WHERE legacy_membership_id = ?
                """, arguments: [sourceID]) {
                let entryID: String? = ledger["entry_id"]
                guard let entryID else {
                    report.userRemovedEntries += 1
                    continue
                }
                guard let playlistID = targetPlaylist.itemID,
                      let recordingID = targetRecording.itemID else {
                    report.brokenLedgerEntries += 1
                    continue
                }
                let found = try String.fetchOne(db, sql: """
                    SELECT id FROM trop_v2_playlist_entry
                    WHERE id = ? AND playlist_id = ? AND recording_id = ?
                    """, arguments: [entryID, playlistID, recordingID])
                if found == nil {
                    report.brokenLedgerEntries += 1
                } else {
                    report.existingEntries += 1
                }
            } else {
                report.newEntries += 1
            }
        }
        return report
    }
}
