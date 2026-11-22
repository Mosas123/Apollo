import Foundation
import GRDB

/// V2-only backup/restore engine. This is intentionally not wired to Settings
/// until full legacy+V2 round-trip recovery has been independently verified.
///
/// Restore accepts a validated archive only when ALL V2 tables are empty.
/// It never deletes, updates or overwrites the active user library.
enum TropLibraryV2RecoveryStore {
    struct Preview: Sendable, Equatable {
        let recordings: Int
        let playlists: Int
        let entries: Int
        let radioFavorites: Int
        let omittedPrivateAliases: Int
    }

    static func preview(_ data: Data) throws -> Preview {
        let source = try TropLibraryV2RecoveryArchive.decode(data).library
        return Preview(
            recordings: source.items.filter { $0.kind == "recording" }.count,
            playlists: source.items.filter { $0.kind == "playlist" }.count,
            entries: source.playlistEntries.count,
            radioFavorites: source.radioFavorites.count,
            omittedPrivateAliases: source.omittedPrivateAliases
        )
    }

    /// Fetches six V2 tables from one consistent GRDB read transaction.
    /// No legacy account tokens, files, stream URLs, caches or history.
    /// Runs in the *caller's* GRDB read transaction. Combined archives
    /// reuse this to ensure legacy and V2 represent the same instant.
    static func snapshot(in db: Database) throws -> TropLibraryV2RecoverySnapshot {
            let items = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, kind, title, artist_or_author, duration_seconds,
                           saved_at, liked_at, created_at, modified_at
                    FROM trop_v2_item ORDER BY id
                    """
            ).map { row in
                TropLibraryV2RecoverySnapshot.Item(
                    id: row["id"], kind: row["kind"],
                    title: row["title"], artistOrAuthor: row["artist_or_author"],
                    durationSeconds: row["duration_seconds"],
                    savedAt: row["saved_at"], likedAt: row["liked_at"],
                    createdAt: row["created_at"], modifiedAt: row["modified_at"]
                )
            }

            let aliasRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, item_id, kind, provider, source_scope, external_id
                    FROM trop_v2_source_alias ORDER BY id
                    """
            )
            var aliases: [TropLibraryV2RecoverySnapshot.Alias] = []
            var omitted = 0
            for row in aliasRows {
                let provider: String = row["provider"]
                let externalID: String = row["external_id"]
                if !TropLibraryV2RecoveryArchive.isPortableAlias(
                    provider: provider, externalID: externalID
                ) {
                    omitted += 1
                    continue
                }
                aliases.append(
                    TropLibraryV2RecoverySnapshot.Alias(
                        id: row["id"], itemID: row["item_id"],
                        kind: row["kind"], provider: provider,
                        scope: row["source_scope"], externalID: externalID
                    )
                )
            }

            let entries = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, playlist_id, recording_id, position, created_at
                    FROM trop_v2_playlist_entry
                    ORDER BY playlist_id, position, created_at, id
                    """
            ).map { row in
                TropLibraryV2RecoverySnapshot.PlaylistEntry(
                    id: row["id"], playlistID: row["playlist_id"],
                    recordingID: row["recording_id"], position: row["position"],
                    createdAt: row["created_at"]
                )
            }

            let radios = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, station_uuid, name, subtitle, added_at
                    FROM trop_v2_radio_favorite ORDER BY id
                    """
            ).map { row in
                TropLibraryV2RecoverySnapshot.RadioFavorite(
                    id: row["id"], stationUUID: row["station_uuid"],
                    name: row["name"], subtitle: row["subtitle"],
                    addedAt: row["added_at"]
                )
            }

            let ledger = try Row.fetchAll(
                db,
                sql: """
                    SELECT legacy_membership_id, entry_id, imported_at
                    FROM trop_v2_legacy_import_entry ORDER BY legacy_membership_id
                    """
            ).map { row in
                TropLibraryV2RecoverySnapshot.ImportLedger(
                    legacyMembershipID: row["legacy_membership_id"],
                    entryID: row["entry_id"], importedAt: row["imported_at"]
                )
            }

            let relations = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, owner_item_id, link_kind, external_id, created_at
                    FROM trop_v2_legacy_relation ORDER BY id
                    """
            ).map { row in
                TropLibraryV2RecoverySnapshot.LegacyRelation(
                    id: row["id"], ownerItemID: row["owner_item_id"],
                    linkKind: row["link_kind"], externalID: row["external_id"],
                    createdAt: row["created_at"]
                )
            }

            let snapshot = TropLibraryV2RecoverySnapshot(
                items: items, aliases: aliases, playlistEntries: entries,
                radioFavorites: radios, importLedger: ledger,
                legacyRelations: relations, omittedPrivateAliases: omitted
            )
            try TropLibraryV2RecoveryArchive.validate(snapshot)
            return snapshot
    }

    static func snapshot() async throws -> TropLibraryV2RecoverySnapshot {
        guard DatabaseService.shared.usesPersistentStore else {
            throw TropLibraryV2RecoveryError.temporaryDatabase
        }
        return try await DatabaseService.shared.read { db in
            try snapshot(in: db)
        }
    }

    static func export() async throws -> Data {
        let library = try await snapshot()
        return try TropLibraryV2RecoveryArchive.encode(library)
    }

    /// Internal staging entry point. Not reachable from user settings yet.
    /// One atomic write: failures leave the destination empty.
    static func restoreIntoEmptyLibrary(_ archive: Data) async throws -> Preview {
        guard DatabaseService.shared.usesPersistentStore else {
            throw TropLibraryV2RecoveryError.temporaryDatabase
        }
        let library = try TropLibraryV2RecoveryArchive.decode(archive).library
        let preview = try preview(archive)

        try await DatabaseService.shared.write { db in
            let tables = [
                "trop_v2_item",
                "trop_v2_source_alias",
                "trop_v2_playlist_entry",
                "trop_v2_radio_favorite",
                "trop_v2_legacy_import_entry",
                "trop_v2_legacy_relation"
            ]
            for table in tables {
                // Only fixed developer-authored table names enter this SQL.
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
                guard count == 0 else {
                    throw TropLibraryV2RecoveryError.existingLibrary
                }
            }

            // The v12 ledger keys are local INTEGER row IDs, not globally
            // scoped identities. Refuse foreign legacy memberships until
            // provenance includes an origin identifier in a future schema.
            if !library.importLedger.isEmpty {
                let legacyRows = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM playlist_song_map"
                ) ?? 0
                guard legacyRows == 0 else {
                    throw TropLibraryV2RecoveryError.legacySourceConflict
                }
            }

            for item in library.items {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_item
                            (id, kind, title, artist_or_author, duration_seconds,
                             saved_at, liked_at, created_at, modified_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        item.id, item.kind, item.title, item.artistOrAuthor,
                        item.durationSeconds, item.savedAt, item.likedAt,
                        item.createdAt, item.modifiedAt
                    ]
                )
            }
            for alias in library.aliases {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_source_alias
                            (id, item_id, kind, provider, source_scope, external_id)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        alias.id, alias.itemID, alias.kind, alias.provider,
                        alias.scope, alias.externalID
                    ]
                )
            }
            for entry in library.playlistEntries {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_playlist_entry
                            (id, playlist_id, recording_id, position, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        entry.id, entry.playlistID, entry.recordingID,
                        entry.position, entry.createdAt
                    ]
                )
            }
            for radio in library.radioFavorites {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_radio_favorite
                            (id, station_uuid, name, subtitle, added_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        radio.id, radio.stationUUID, radio.name,
                        radio.subtitle, radio.addedAt
                    ]
                )
            }
            for ledger in library.importLedger {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_legacy_import_entry
                            (legacy_membership_id, entry_id, imported_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [
                        ledger.legacyMembershipID, ledger.entryID,
                        ledger.importedAt
                    ]
                )
            }
            for relation in library.legacyRelations {
                try db.execute(
                    sql: """
                        INSERT INTO trop_v2_legacy_relation
                            (id, owner_item_id, link_kind, external_id, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        relation.id, relation.ownerItemID, relation.linkKind,
                        relation.externalID, relation.createdAt
                    ]
                )
            }
        }
        return preview
    }
}
