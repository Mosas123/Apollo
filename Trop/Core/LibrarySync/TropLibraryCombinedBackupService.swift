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
    }

    static func preview(_ data: Data) throws -> Preview {
        let library = try TropLibraryCombinedBackupArchive.decode(data).library
        return Preview(
            legacyTracks: library.legacy.tracks.count,
            legacyPlaylists: library.legacy.playlists.count,
            legacyPlaylistEntries: library.legacy.playlistEntries.count,
            v2Recordings: library.libraryV2.items.filter { $0.kind == "recording" }.count,
            v2Playlists: library.libraryV2.items.filter { $0.kind == "playlist" }.count,
            v2PlaylistEntries: library.libraryV2.playlistEntries.count,
            radioFavorites: library.libraryV2.radioFavorites.count,
            omittedPrivateAliases: library.libraryV2.omittedPrivateAliases,
            legacyLedgerEntriesNeedingOrigin: library.libraryV2.importLedger.count
        )
    }

    static func snapshot() async throws -> TropLibraryCombinedBackupSnapshot {
        guard DatabaseService.shared.usesPersistentStore else {
            throw TropLibraryCombinedBackupError.temporaryDatabase
        }
        return try await DatabaseService.shared.read { db in
            let legacy = try TropLibraryBackupService.snapshot(in: db)
            let v2 = try TropLibraryV2RecoveryStore.snapshot(in: db)
            return TropLibraryCombinedBackupSnapshot(legacy: legacy, libraryV2: v2)
        }
    }

    static func export() async throws -> Data {
        try TropLibraryCombinedBackupArchive.encode(await snapshot())
    }
}
