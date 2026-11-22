import CryptoKit
import Foundation

/// Portable, metadata-only V2 snapshot. IDs of add-ons that may embed
/// private manifest material are deliberately omitted by the export service.
/// An omitted alias cannot be used to play audio after restoration.
struct TropLibraryV2RecoverySnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let id: String
        let kind: String
        let title: String
        let artistOrAuthor: String?
        let durationSeconds: Int
        let savedAt: Date?
        let likedAt: Date?
        let createdAt: Date
        let modifiedAt: Date
    }

    struct Alias: Codable, Equatable, Sendable {
        let id: String
        let itemID: String
        let kind: String
        let provider: String
        let scope: String
        let externalID: String
    }

    struct PlaylistEntry: Codable, Equatable, Sendable {
        let id: String
        let playlistID: String
        let recordingID: String
        let position: Int
        let createdAt: Date
    }

    struct RadioFavorite: Codable, Equatable, Sendable {
        let id: String
        let stationUUID: String
        let name: String
        let subtitle: String
        let addedAt: Date
    }

    struct ImportLedger: Codable, Equatable, Sendable {
        let legacyMembershipID: Int64
        let entryID: String?
        let importedAt: Date
    }

    struct LegacyRelation: Codable, Equatable, Sendable {
        let id: String
        let ownerItemID: String
        let linkKind: String
        let externalID: String
        let createdAt: Date
    }

    let items: [Item]
    let aliases: [Alias]
    let playlistEntries: [PlaylistEntry]
    let radioFavorites: [RadioFavorite]
    let importLedger: [ImportLedger]
    let legacyRelations: [LegacyRelation]
    let omittedPrivateAliases: Int
}

struct TropLibraryV2RecoveryEnvelope: Codable, Sendable {
    let format: String
    let version: Int
    let createdAt: Date
    let payloadSHA256: String
    let library: TropLibraryV2RecoverySnapshot
}

enum TropLibraryV2RecoveryError: Error, Equatable, Sendable {
    case unsupportedVersion
    case invalidData
    case oversized
    case checksumMismatch
    case existingLibrary
    case legacySourceConflict
    case temporaryDatabase
}

/// SHA-256 catches accidental corruption; it does not authenticate the
/// origin of an archive and is not encryption. Never log archive bytes.
enum TropLibraryV2RecoveryArchive {
    static let format = "trop-library-v2-metadata"
    static let version = 2
    static let maximumBytes = 24 * 1_024 * 1_024
    static let maximumRecords = 150_000

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

    static func encode(_ library: TropLibraryV2RecoverySnapshot) throws -> Data {
        try validate(library)
        let payload = try encoder().encode(library)
        guard payload.count <= maximumBytes else { throw TropLibraryV2RecoveryError.oversized }
        let envelope = TropLibraryV2RecoveryEnvelope(
            format: format, version: version, createdAt: Date(),
            payloadSHA256: digest(payload), library: library
        )
        let data = try encoder().encode(envelope)
        guard data.count <= maximumBytes else { throw TropLibraryV2RecoveryError.oversized }
        return data
    }

    static func decode(_ data: Data) throws -> TropLibraryV2RecoveryEnvelope {
        guard data.count <= maximumBytes else { throw TropLibraryV2RecoveryError.oversized }
        let envelope: TropLibraryV2RecoveryEnvelope
        do {
            envelope = try decoder().decode(TropLibraryV2RecoveryEnvelope.self, from: data)
        } catch {
            throw TropLibraryV2RecoveryError.invalidData
        }
        guard envelope.format == format, envelope.version == version else {
            throw TropLibraryV2RecoveryError.unsupportedVersion
        }
        let payload = try encoder().encode(envelope.library)
        guard digest(payload) == envelope.payloadSHA256 else {
            throw TropLibraryV2RecoveryError.checksumMismatch
        }
        try validate(envelope.library)
        return envelope
    }

    /// Export only opaque IDs from known non-addon catalogues. Unknown
    /// providers and addon:base64 IDs could include personal manifests.
    static func isPortableAlias(provider: String, externalID: String) -> Bool {
        let allowed: Set<String> = [
            "youtube", "spotify", "qobuz", "audius",
            "jiosaavn", "jamendo", "musicbrainz"
        ]
        return allowed.contains(provider)
            && !externalID.hasPrefix("addon:")
            && !externalID.contains("://")
            && !externalID.contains("?")
            && !externalID.contains("#")
    }

    static func validate(_ library: TropLibraryV2RecoverySnapshot) throws {
        let total = [
            library.items.count, library.aliases.count,
            library.playlistEntries.count, library.radioFavorites.count,
            library.importLedger.count, library.legacyRelations.count
        ].reduce(0, +)
        guard total <= maximumRecords, library.omittedPrivateAliases >= 0 else {
            throw TropLibraryV2RecoveryError.invalidData
        }

        func unique(_ ids: [String]) -> Bool { Set(ids).count == ids.count }
        func canonical(_ id: String) -> Bool {
            TropLibraryV2IdentityPolicy.isCanonicalID(id)
        }
        func safeDate(_ value: Date) -> Bool {
            value.timeIntervalSince1970.isFinite
        }

        guard unique(library.items.map(\.id)),
              unique(library.aliases.map(\.id)),
              unique(library.playlistEntries.map(\.id)),
              unique(library.radioFavorites.map(\.id)),
              unique(library.legacyRelations.map(\.id)),
              Set(library.importLedger.map(\.legacyMembershipID)).count
                == library.importLedger.count
        else { throw TropLibraryV2RecoveryError.invalidData }

        var kinds: [String: String] = [:]
        for item in library.items {
            guard canonical(item.id),
                  let kind = TropLibraryV2Kind(rawValue: item.kind),
                  (try? TropLibraryV2IdentityPolicy.checkedTitle(item.title)) != nil,
                  (item.artistOrAuthor == nil ||
                    (try? TropLibraryV2IdentityPolicy.checkedOptionalText(item.artistOrAuthor)) != nil),
                  item.durationSeconds >= 0,
                  safeDate(item.createdAt), safeDate(item.modifiedAt),
                  item.savedAt.map(safeDate) != false,
                  item.likedAt.map(safeDate) != false,
                  (item.likedAt == nil || kind == .recording)
            else { throw TropLibraryV2RecoveryError.invalidData }
            kinds[item.id] = item.kind
        }

        var aliasKeys = Set<String>()
        for alias in library.aliases {
            guard canonical(alias.id), kinds[alias.itemID] == alias.kind,
                  isPortableAlias(provider: alias.provider, externalID: alias.externalID),
                  (try? TropLibraryV2SourceAlias(
                    provider: alias.provider, scope: alias.scope,
                    externalID: alias.externalID
                  )) != nil
            else { throw TropLibraryV2RecoveryError.invalidData }
            let key = alias.provider + "\u{001F}" + alias.scope
                + "\u{001F}" + alias.kind + "\u{001F}" + alias.externalID
            guard aliasKeys.insert(key).inserted else {
                throw TropLibraryV2RecoveryError.invalidData
            }
        }

        let entryIDs = Set(library.playlistEntries.map(\.id))
        for entry in library.playlistEntries {
            guard canonical(entry.id), kinds[entry.playlistID] == "playlist",
                  kinds[entry.recordingID] == "recording", entry.position >= 0,
                  safeDate(entry.createdAt)
            else { throw TropLibraryV2RecoveryError.invalidData }
        }

        var stationIDs = Set<String>()
        for radio in library.radioFavorites {
            guard canonical(radio.id), UUID(uuidString: radio.stationUUID) != nil,
                  (try? TropLibraryV2IdentityPolicy.checkedTitle(radio.name)) != nil,
                  (radio.subtitle.isEmpty ||
                    (try? TropLibraryV2IdentityPolicy.checkedOptionalText(radio.subtitle)) != nil),
                  safeDate(radio.addedAt), stationIDs.insert(radio.stationUUID).inserted
            else { throw TropLibraryV2RecoveryError.invalidData }
        }

        for ledger in library.importLedger {
            guard ledger.legacyMembershipID > 0, safeDate(ledger.importedAt),
                  ledger.entryID == nil || (
                    ledger.entryID.map(canonical) == true
                        && ledger.entryID.map(entryIDs.contains) == true
                  )
            else { throw TropLibraryV2RecoveryError.invalidData }
        }

        var relationKeys = Set<String>()
        for link in library.legacyRelations {
            guard canonical(link.id), kinds[link.ownerItemID] != nil,
                  (link.linkKind == "episode_podcast" && kinds[link.ownerItemID] == "episode")
                    || (link.linkKind == "album_playlist" && kinds[link.ownerItemID] == "album")
            else { throw TropLibraryV2RecoveryError.invalidData }
            guard (try? TropLibraryV2SourceAlias(
                provider: "youtube", externalID: link.externalID
            )) != nil, safeDate(link.createdAt) else {
                throw TropLibraryV2RecoveryError.invalidData
            }
            guard relationKeys.insert(link.ownerItemID + ":" + link.linkKind).inserted else {
                throw TropLibraryV2RecoveryError.invalidData
            }
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
