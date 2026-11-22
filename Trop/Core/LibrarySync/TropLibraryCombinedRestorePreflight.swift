import Foundation
import GRDB

/// Must run *inside* the eventual restore's one database write transaction.
/// A preflight in a separate read would be racy; never enable user restore
/// based on a previous read or assume that an uninitialized DB is empty.
enum TropLibraryCombinedRestorePreflight {
    enum Blocker: Error, Equatable, Sendable {
        case missingSchema(String)
        case occupiedDestination(String)
    }

    /// Only hard-coded schema names enter SQL. Do not infer table names from
    /// an archive. Include old playback history and downloads because a
    /// "blank library" with hidden user data is not a safe restore target.
    static let protectedTables: [String] = [
        "song", "album", "artist", "playlist", "playlist_song_map",
        "podcast", "episode", "podcast_episode_map", "event", "play_count",
        "downloaded_track", "speed_dial", "format",
        "trop_v2_item", "trop_v2_source_alias", "trop_v2_playlist_entry",
        "trop_v2_radio_favorite", "trop_v2_legacy_import_entry",
        "trop_v2_legacy_relation", "trop_v2_foreign_import_tombstone"
    ]

    static let requiredTables: [String] = [
        "song", "album", "artist", "playlist", "playlist_song_map",
        "podcast", "episode",
        "trop_v2_item", "trop_v2_source_alias", "trop_v2_playlist_entry",
        "trop_v2_radio_favorite", "trop_v2_legacy_import_entry",
        "trop_v2_legacy_relation", "trop_v2_foreign_import_tombstone",
        "trop_v2_library_origin"
    ]

    static func requireEmpty(_ db: Database) throws {
        for table in requiredTables {
            guard try db.tableExists(table) else {
                throw Blocker.missingSchema(table)
            }
        }

        for table in protectedTables {
            guard try db.tableExists(table) else { continue }
            let occupied = try Int.fetchOne(
                db, sql: "SELECT 1 FROM \(table) LIMIT 1"
            ) != nil
            guard !occupied else {
                throw Blocker.occupiedDestination(table)
            }
        }
    }
}
