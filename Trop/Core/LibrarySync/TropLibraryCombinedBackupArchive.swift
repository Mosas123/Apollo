import CryptoKit
import Foundation

/// Experimental metadata-only transport for legacy AND V2 in one container.
/// It is deliberately not a restoration format exposed to the user yet.
/// Existing .tropbackup v1 and V2 JSON archives remain independently readable.
struct TropLibraryCombinedBackupSnapshot: Codable, Equatable, Sendable {
    let legacy: TropLibraryBackupSnapshot
    let libraryV2: TropLibraryV2RecoverySnapshot
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
    static let version = 1
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

    private static func validate(_ library: TropLibraryCombinedBackupSnapshot) throws {
        // Both sub-archives enforce their own ID, size, row-count and alias
        // allowlists. Reuse those validators instead of maintaining a second
        // set of rules that could accidentally weaken privacy checks.
        do {
            _ = try TropLibraryBackupArchive.encode(library: library.legacy)
            _ = try TropLibraryV2RecoveryArchive.encode(library.libraryV2)
        } catch {
            throw TropLibraryCombinedBackupError.invalidPayload
        }
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
