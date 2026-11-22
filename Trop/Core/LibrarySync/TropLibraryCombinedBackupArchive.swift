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

    struct ForeignTombstone: Codable, Equatable, Sendable {
        let originScope: String
        let sourceMembershipID: Int64
        let entryID: String?
        let importedAt: Date
    }

    /// Unsubscribed / unsaved entities that participate in a podcast link.
    /// Nil dates retain their original state; do not invent subscriptions.
    struct RelatedPodcast: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let subscribedAt: Date?
    }
    struct RelatedEpisode: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let podcastID: String?
        let duration: Int
        let isPlayed: Bool
        let savedAt: Date?
    }
    struct PodcastEpisodeMembership: Codable, Equatable, Sendable {
        let podcastID: String
        let episodeID: String
        let position: Int
    }

    /// Optional public provider IDs from legacy tables. These are NOT
    /// Trop-owned primary identities and never start a provider session.
    struct LegacyAlbumSource: Codable, Equatable, Sendable {
        let albumID: String
        let sourcePlaylistID: String
    }
    struct LegacyArtistSource: Codable, Equatable, Sendable {
        let artistID: String
        let sourceChannelID: String
    }

    let legacy: TropLibraryBackupSnapshot
    let libraryV2: TropLibraryV2RecoverySnapshot
    let legacyMemberships: [LegacyMembership]
    let originScope: String
    let foreignTombstones: [ForeignTombstone]
    let relatedPodcasts: [RelatedPodcast]
    let relatedEpisodes: [RelatedEpisode]
    let podcastEpisodeMemberships: [PodcastEpisodeMembership]
    let legacyAlbumSources: [LegacyAlbumSource]
    let legacyArtistSources: [LegacyArtistSource]

    init(
        legacy: TropLibraryBackupSnapshot,
        libraryV2: TropLibraryV2RecoverySnapshot,
        legacyMemberships: [LegacyMembership],
        originScope: String,
        foreignTombstones: [ForeignTombstone],
        relatedPodcasts: [RelatedPodcast] = [],
        relatedEpisodes: [RelatedEpisode] = [],
        podcastEpisodeMemberships: [PodcastEpisodeMembership] = [],
        legacyAlbumSources: [LegacyAlbumSource] = [],
        legacyArtistSources: [LegacyArtistSource] = []
    ) {
        self.legacy = legacy
        self.libraryV2 = libraryV2
        self.legacyMemberships = legacyMemberships
        self.originScope = originScope
        self.foreignTombstones = foreignTombstones
        self.relatedPodcasts = relatedPodcasts
        self.relatedEpisodes = relatedEpisodes
        self.podcastEpisodeMemberships = podcastEpisodeMemberships
        self.legacyAlbumSources = legacyAlbumSources
        self.legacyArtistSources = legacyArtistSources
    }
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
    static let version = 5
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

        // Podcast_episode_map is a separate ordered relationship in the
        // real legacy schema. Reject dangling, forged or duplicated links.
        func validLegacyID(_ id: String) -> Bool {
            !id.isEmpty && id.utf8.count <= 512
                && !id.contains("://") && !id.contains("?")
                && !id.contains("#") && !id.hasPrefix("/")
                && !id.contains("\\")
                && !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
        func validText(_ string: String) -> Bool {
            string.utf8.count <= 2_048
                && !string.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
        guard library.relatedPodcasts.count + library.relatedEpisodes.count
                + library.podcastEpisodeMemberships.count
                    <= TropLibraryBackupArchive.maximumRecords
        else { throw TropLibraryCombinedBackupError.invalidPayload }
        let savedPodcasts = Set(library.legacy.podcasts.map(\.id))
        let savedEpisodes = Set(library.legacy.episodes.map(\.id))
        let relatedPodcastIDs = library.relatedPodcasts.map(\.id)
        let relatedEpisodeIDs = library.relatedEpisodes.map(\.id)
        guard Set(relatedPodcastIDs).count == relatedPodcastIDs.count,
              Set(relatedEpisodeIDs).count == relatedEpisodeIDs.count,
              savedPodcasts.isDisjoint(with: relatedPodcastIDs),
              savedEpisodes.isDisjoint(with: relatedEpisodeIDs),
              library.relatedPodcasts.allSatisfy({
                  validLegacyID($0.id) && validText($0.name)
                      && $0.subscribedAt == nil
              }),
              library.relatedEpisodes.allSatisfy({
                  validLegacyID($0.id) && validText($0.title)
                      && $0.podcastID.map(validLegacyID) != false
                      && $0.duration >= 0 && $0.savedAt == nil
              })
        else { throw TropLibraryCombinedBackupError.invalidPayload }
        let allPodcasts = savedPodcasts.union(relatedPodcastIDs)
        let allEpisodes = savedEpisodes.union(relatedEpisodeIDs)
        var linkKeys = Set<String>()
        for link in library.podcastEpisodeMemberships {
            guard validLegacyID(link.podcastID), validLegacyID(link.episodeID),
                  link.position >= 0,
                  allPodcasts.contains(link.podcastID),
                  allEpisodes.contains(link.episodeID),
                  linkKeys.insert(link.podcastID + ":" + link.episodeID).inserted
            else { throw TropLibraryCombinedBackupError.invalidPayload }
        }

        // Provider source pointers must belong to saved legacy entities.
        // They can point to a remote catalogue entry not in local playlists:
        // never treat sourcePlaylistID or sourceChannelID as a local FK.
        let albumIDs = Set(library.legacy.albums.map(\.id))
        let artistIDs = Set(library.legacy.artists.map(\.id))
        guard library.legacyAlbumSources.count + library.legacyArtistSources.count
                <= TropLibraryBackupArchive.maximumRecords,
              Set(library.legacyAlbumSources.map(\.albumID)).count
                == library.legacyAlbumSources.count,
              Set(library.legacyArtistSources.map(\.artistID)).count
                == library.legacyArtistSources.count,
              library.legacyAlbumSources.allSatisfy({
                  albumIDs.contains($0.albumID) && validLegacyID($0.sourcePlaylistID)
              }),
              library.legacyArtistSources.allSatisfy({
                  artistIDs.contains($0.artistID) && validLegacyID($0.sourceChannelID)
              })
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
        // A stable origin UUID is persisted at installation migration time.
        func canonicalScope(_ scope: String) -> Bool {
            guard let uuid = UUID(uuidString: scope) else { return false }
            return uuid.uuidString.lowercased() == scope
        }
        guard canonicalScope(library.originScope),
              library.foreignTombstones.count <= TropLibraryBackupArchive.maximumRecords
        else { throw TropLibraryCombinedBackupError.invalidPayload }
        // Foreign tombstone references are historical: a V2 entry may
        // itself have been deleted after this import. Require canonical UUID
        // syntax, but never require an active entry to still exist.
        var keys = Set<String>()
        for tombstone in library.foreignTombstones {
            guard canonicalScope(tombstone.originScope),
                  tombstone.sourceMembershipID > 0,
                  tombstone.importedAt.timeIntervalSince1970.isFinite,
                  tombstone.entryID == nil
                    || tombstone.entryID.map(TropLibraryV2IdentityPolicy.isCanonicalID) == true
            else { throw TropLibraryCombinedBackupError.invalidPayload }
            let key = tombstone.originScope + ":" + String(tombstone.sourceMembershipID)
            guard keys.insert(key).inserted else {
                throw TropLibraryCombinedBackupError.invalidPayload
            }
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
