import Foundation
import GRDB

/// Staging-only unified archive service. Nothing is enabled in Settings.
/// Both halves are fetched under ONE GRDB read transaction, so user edits
/// cannot sneak between independent legacy and V2 snapshots.
enum TropLibraryCombinedBackupService {
    struct Preview: Equatable, Sendable {
        let legacyTracks: Int
        let legacyPlaylists: Int
        let legacyPlaylistEntries: Int
        let v2Recordings: Int
        let v2Playlists: Int
        let v2PlaylistEntries: Int
        let radioFavorites: Int
        let omittedPrivateAliases: Int
        let legacyLedgerEntriesNeedingOrigin: Int
        let sourceMemberships: Int
        let ledgerEntriesWithMissingMembership: Int
    }

    static func preview(_ data: Data) throws -> Preview {
        let library = try TropLibraryCombinedBackupArchive.decode(data).library
        let membershipIDs = Set(library.legacyMemberships.map(\.sourceRowID))
        return Preview(
            legacyTracks: library.legacy.tracks.count,
            legacyPlaylists: library.legacy.playlists.count,
            legacyPlaylistEntries: library.legacy.playlistEntries.count,
            v2Recordings: library.libraryV2.items.filter { $0.kind == "recording" }.count,
            v2Playlists: library.libraryV2.items.filter { $0.kind == "playlist" }.count,
            v2PlaylistEntries: library.libraryV2.playlistEntries.count,
            radioFavorites: library.libraryV2.radioFavorites.count,
            omittedPrivateAliases: library.libraryV2.omittedPrivateAliases,
            legacyLedgerEntriesNeedingOrigin: library.libraryV2.importLedger.count,
            sourceMemberships: library.legacyMemberships.count,
            ledgerEntriesWithMissingMembership: library.libraryV2.importLedger.filter {
                !membershipIDs.contains($0.legacyMembershipID)
            }.count
        )
    }

    static func snapshot() async throws -> TropLibraryCombinedBackupSnapshot {
        guard DatabaseService.shared.usesPersistentStore else {
            throw TropLibraryCombinedBackupError.temporaryDatabase
        }
        return try await DatabaseService.shared.read { db in
            let legacy = try TropLibraryBackupService.snapshot(in: db)
            let v2 = try TropLibraryV2RecoveryStore.snapshot(in: db)
            let memberships = try Row.fetchAll(
                db, sql: """
                    SELECT id, playlist_id, song_id, position
                    FROM playlist_song_map ORDER BY playlist_id, position, id
                    """
            ).map { row in
                TropLibraryCombinedBackupSnapshot.LegacyMembership(
                    sourceRowID: row["id"],
                    playlistID: row["playlist_id"], songID: row["song_id"],
                    position: row["position"]
                )
            }
            return TropLibraryCombinedBackupSnapshot(
                legacy: legacy, libraryV2: v2,
                legacyMemberships: memberships
            )
        }
    }

    static func export() async throws -> Data {
        let library = try await snapshot()
        return try TropLibraryCombinedBackupArchive.encode(library)
    }
}
