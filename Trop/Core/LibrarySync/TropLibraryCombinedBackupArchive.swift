import CryptoKit
import Foundation

/// Experimental metadata-only transport for legacy AND V2 in one container.
/// It is deliberately not a restoration format exposed to the user yet.
/// Existing .tropbackup v1 and V2 JSON archives remain independently readable.
struct TropLibraryCombinedBackupSnapshot: Codable, Equatable, Sendable {
    /// Origin-local row identity is preserved separately; legacy .tropbackup
    /// V1 remains byte-compatible, and no destination ID is assumed equal.
    struct LegacyMembership: Codable, Equatable, Sendable {
        let sourceRowID: Int64
        let playlistID: String
        let songID: String
        let position: Int
    }

    let legacy: TropLibraryBackupSnapshot
    let libraryV2: TropLibraryV2RecoverySnapshot
    let legacyMemberships: [LegacyMembership]
}

struct TropLibraryCombinedBackupEnvelope: Codable, Sendable {
    let format: String
    let version: Int
    let createdAt: Date
    let payloadSHA256: String
    let library: TropLibraryCombinedBackupSnapshot
}

enum TropLibraryCombinedBackupError: Error, Equatable, Sendable {
    case unsupportedVersion
    case invalidPayload
    case oversized
    case checksumMismatch
    case temporaryDatabase
}

/// SHA-256 detects corruption, NOT a forgery or untrusted author.
/// No credentials, downloaded audio, app settings or source manifest URLs.
/// Import ledger IDs are device-local and must not be used for restore on a
/// foreign device without an explicit origin/provenance mapping.
enum TropLibraryCombinedBackupArchive {
    static let format = "trop-library-combined-metadata"
    static let version = 2
    static let maximumBytes = 40 * 1_024 * 1_024

    private static func encoder() -> JSONEncoder {
        let result = JSONEncoder()
        result.outputFormatting = [.sortedKeys]
        result.dateEncodingStrategy = .millisecondsSince1970
        return result
    }

    private static func decoder() -> JSONDecoder {
        let result = JSONDecoder()
        result.dateDecodingStrategy = .millisecondsSince1970
        return result
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A playlist membership's integer row ID has meaning only in its
    /// source database. Validate the *complete* ID↔tuple map and preserve
    /// the stable playlist order; do not guess IDs during restoration.
    private struct MembershipKey: Hashable {
        let playlistID: String
        let songID: String
        let position: Int
    }

    private static func validate(_ library: TropLibraryCombinedBackupSnapshot) throws {
        // Existing allowlists retain authority for both sub-archives.
        do {
            _ = try TropLibraryBackupArchive.encode(library: library.legacy)
            _ = try TropLibraryV2RecoveryArchive.encode(library.libraryV2)
        } catch {
            throw TropLibraryCombinedBackupError.invalidPayload
        }
        guard library.legacyMemberships.count
                == library.legacy.playlistEntries.count,
              library.legacyMemberships.count <= TropLibraryBackupArchive.maximumRecords
        else { throw TropLibraryCombinedBackupError.invalidPayload }

        let ids = library.legacyMemberships.map(\.sourceRowID)
        guard ids.allSatisfy({ $0 > 0 }),
              Set(ids).count == ids.count else {
            throw TropLibraryCombinedBackupError.invalidPayload
        }

        var expected: [MembershipKey: Int] = [:]
        for entry in library.legacy.playlistEntries {
            let key = MembershipKey(
                playlistID: entry.playlistId,
                songID: entry.songId,
                position: entry.position
            )
            expected[key, default: 0] += 1
        }
        for entry in library.legacyMemberships {
            let key = MembershipKey(
                playlistID: entry.playlistID,
                songID: entry.songID,
                position: entry.position
            )
            guard let count = expected[key], count > 0 else {
                throw TropLibraryCombinedBackupError.invalidPayload
            }
            if count == 1 { expected.removeValue(forKey: key) }
            else { expected[key] = count - 1 }
        }
        guard expected.isEmpty else {
            throw TropLibraryCombinedBackupError.invalidPayload
        }
        // Ledger tombstones can legitimately reference deleted origin
        // memberships. They remain recorded but are not safe to blindly
        // recreate on another device. The preview counts those orphans.
    }

    static func encode(
        _ library: TropLibraryCombinedBackupSnapshot,
        createdAt: Date = Date()
    ) throws -> Data {
        try validate(library)
        let payload = try encoder().encode(library)
        guard payload.count <= maximumBytes else {
            throw TropLibraryCombinedBackupError.oversized
        }
        let envelope = TropLibraryCombinedBackupEnvelope(
            format: format, version: version, createdAt: createdAt,
            payloadSHA256: digest(payload), library: library
        )
        let data = try encoder().encode(envelope)
        guard data.count <= maximumBytes else {
            throw TropLibraryCombinedBackupError.oversized
        }
        return data
    }

    static func decode(_ data: Data) throws -> TropLibraryCombinedBackupEnvelope {
        guard data.count <= maximumBytes else {
            throw TropLibraryCombinedBackupError.oversized
        }
        let envelope: TropLibraryCombinedBackupEnvelope
        do {
            envelope = try decoder().decode(
                TropLibraryCombinedBackupEnvelope.self, from: data
            )
        } catch {
            throw TropLibraryCombinedBackupError.invalidPayload
        }
        guard envelope.format == format, envelope.version == version else {
            throw TropLibraryCombinedBackupError.unsupportedVersion
        }
        let payload = try encoder().encode(envelope.library)
        guard digest(payload) == envelope.payloadSHA256 else {
            throw TropLibraryCombinedBackupError.checksumMismatch
        }
        try validate(envelope.library)
        return envelope
    }
}
