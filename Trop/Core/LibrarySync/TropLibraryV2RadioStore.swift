import Foundation
import GRDB

/// Radio stations are separate from recordings. Their stable Radio Browser
/// UUID is stored as a source reference, not as the Trop-owned primary key.
/// No streaming endpoint or signed audio URL is persisted.
enum TropLibraryV2RadioStore {
    struct Favorite: Sendable, Equatable, Identifiable {
        let id: String
        let stationUUID: String
        let name: String
        let subtitle: String
    }

    static func canonicalStationUUID(_ value: String) throws -> String {
        guard let uuid = UUID(uuidString: value) else {
            throw TropLibraryV2ValidationError.invalidIdentifier
        }
        return uuid.uuidString.lowercased()
    }

    static func save(station: RadioStation) async throws {
        let stationUUID = try canonicalStationUUID(station.stationuuid)
        let name = try TropLibraryV2IdentityPolicy.checkedTitle(station.name)
        let subtitle = try TropLibraryV2IdentityPolicy.checkedOptionalText(station.subtitle) ?? ""
        let id = TropLibraryV2IdentityPolicy.newID()
        let now = Date()
        try await DatabaseService.shared.write { db in
            try db.execute(
                sql: """
                    INSERT INTO trop_v2_radio_favorite (
                        id, station_uuid, name, subtitle, added_at
                    ) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(station_uuid) DO UPDATE SET
                        name = excluded.name,
                        subtitle = excluded.subtitle
                    """,
                arguments: [id, stationUUID, name, subtitle, now]
            )
        }
    }

    static func remove(stationUUID rawUUID: String) async throws {
        let stationUUID = try canonicalStationUUID(rawUUID)
        try await DatabaseService.shared.write { db in
            try db.execute(
                sql: "DELETE FROM trop_v2_radio_favorite WHERE station_uuid = ?",
                arguments: [stationUUID]
            )
        }
    }

    static func favorites() async throws -> [Favorite] {
        try await DatabaseService.shared.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, station_uuid, name, subtitle
                    FROM trop_v2_radio_favorite
                    ORDER BY added_at DESC, station_uuid
                    """
            ).map { row in
                Favorite(
                    id: row["id"],
                    stationUUID: row["station_uuid"],
                    name: row["name"],
                    subtitle: row["subtitle"]
                )
            }
        }
    }
}
