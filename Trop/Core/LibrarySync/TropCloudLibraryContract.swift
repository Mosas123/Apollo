import Foundation

/// Private iCloud library identity. These UUIDs belong to Trop and never
/// become YouTube video IDs, MusicBrainz MBIDs or playback source URLs.
/// A CloudKit record ID will be based on this scoped, device-independent key.
enum TropCloudItemKind: String, Codable, Hashable, Sendable {
    case recording
    case album
    case artist
    case playlist
    case podcast
    case episode
}

struct TropCloudItemID: Codable, Hashable, Sendable {
    let kind: TropCloudItemKind
    let uuid: UUID

    init(kind: TropCloudItemKind, uuid: UUID = UUID()) {
        self.kind = kind
        self.uuid = uuid
    }

    var storageKey: String {
        "trop:\(kind.rawValue):\(uuid.uuidString.lowercased())"
    }
}

/// Existing provider IDs stay *aliases* to facilitate reversible migration.
/// They never decide whether an item is saved or deleted in the user's cloud.
/// Stream URLs, login cookies and temporary signed links are NOT aliases.
struct TropCloudSourceAlias: Codable, Hashable, Sendable {
    let provider: MusicCatalogSource
    let externalID: String

    init?(provider: MusicCatalogSource, externalID: String) {
        let normalized = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.utf8.count <= 256,
              !normalized.contains("://"),
              !normalized.contains("?"),
              !normalized.contains("#"),
              !normalized.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else { return nil }
        self.provider = provider
        self.externalID = normalized
    }

    var storageKey: String { "\(provider.rawValue):\(externalID)" }
}

/// Metadata only. No audio data, file URLs or local download paths.
/// Episode progress is allowed only for .episode records.
struct TropCloudLibraryRecord: Codable, Equatable, Sendable {
    let id: TropCloudItemID
    var title: String
    var artistOrAuthor: String?
    var sourceAliases: [TropCloudSourceAlias]
    var savedAt: Date
    var modifiedAt: Date
    /// Retain removals as tombstones until all device changes converge.
    var deletedAt: Date?
    var episodeProgressSeconds: TimeInterval?

    var isSaved: Bool { deletedAt == nil }

    /// A valid JSON record can be encoded by the private-cloud adapter.
    /// It does NOT imply that this item may be fetched or played.
    var isValidForCloud: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.utf8.count <= 512
            && (artistOrAuthor?.utf8.count ?? 0) <= 512
            && Set(sourceAliases).count == sourceAliases.count
            && savedAt <= modifiedAt
            && (deletedAt == nil || deletedAt! >= savedAt)
            && (episodeProgressSeconds == nil || (
                id.kind == .episode
                    && episodeProgressSeconds!.isFinite
                    && episodeProgressSeconds! >= 0
            ))
    }
}

enum TropCloudSyncOrigin: String, Sendable {
    case localUserAction
    case youtubeRefresh
    case externalCatalogueRefresh
    case cloudImport
    case fileImport
}

/// Only explicit local user actions generate outbound CloudKit writes.
/// Remote refresh and replay cannot echo a provider's deletions or recursively
/// re-upload the same CloudKit record.
enum TropCloudLibrarySyncPolicy {
    static func shouldExport(origin: TropCloudSyncOrigin) -> Bool {
        origin == .localUserAction
    }

    static func canApplyRemoteRemoval(
        local: TropCloudLibraryRecord,
        incoming: TropCloudLibraryRecord
    ) -> Bool {
        // A CloudKit deletion is not the same as a YouTube library refresh.
        // This phase deliberately defers merging conflicting local edits.
        local.id == incoming.id && incoming.deletedAt != nil
            && local.modifiedAt == incoming.modifiedAt
            && local.deletedAt == incoming.deletedAt
    }
}
