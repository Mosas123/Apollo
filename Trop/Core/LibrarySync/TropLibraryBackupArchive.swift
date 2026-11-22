import CryptoKit
import Foundation

/// Version 1 is a metadata-only escape hatch from legacy provider identities.
/// All fields are explicitly allowlisted. No raw GRDB export, authentication
/// tokens, signed URLs, artwork URLs, local download paths or audio bytes.
struct TropLibraryBackupSnapshot: Codable, Equatable, Sendable {
    struct Track: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let artistName: String?
        let albumName: String?
        let duration: Int
        let liked: Bool
        let inLibrary: Date?
        let isEpisode: Bool
        let createdAt: Date
    }

    struct Album: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let bookmarkedAt: Date
    }

    struct Artist: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let bookmarkedAt: Date
    }

    struct Playlist: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let browseId: String?
        let bookmarkedAt: Date?
        let isEditable: Bool
    }

    struct PlaylistEntry: Codable, Equatable, Sendable {
        let playlistId: String
        let songId: String
        let position: Int
    }

    struct Podcast: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let subscribedAt: Date
    }

    struct Episode: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let podcastId: String?
        let duration: Int
        let isPlayed: Bool
        let savedAt: Date
    }

    let tracks: [Track]
    let albums: [Album]
    let artists: [Artist]
    let playlists: [Playlist]
    let playlistEntries: [PlaylistEntry]
    let podcasts: [Podcast]
    let episodes: [Episode]
}

struct TropLibraryBackupEnvelope: Codable, Sendable {
    let format: String
    let schemaVersion: Int
    let createdAt: Date
    let payloadSHA256: String
    let library: TropLibraryBackupSnapshot
}

struct TropLibraryBackupSummary: Sendable {
    let createdAt: Date
    let tracks: Int
    let likedSongs: Int
    let albums: Int
    let artists: Int
    let playlists: Int
    let playlistEntries: Int
    let podcasts: Int
    let episodes: Int
    let unresolvedEntries: Int
}

enum TropLibraryBackupError: LocalizedError {
    case tooLarge
    case unsupportedFormat
    case invalidPayload
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "The library backup exceeds the supported size."
        case .unsupportedFormat: return "This library backup version is not supported."
        case .invalidPayload: return "The library backup contains invalid metadata."
        case .checksumMismatch: return "The library backup integrity check failed."
        }
    }
}

/// SHA-256 detects accidental corruption; it is NOT a signature or encryption.
/// Restore writes remain disabled until a separate transactional migration and
/// rollback is proven on device.
enum TropLibraryBackupArchive {
    static let format = "trop-library-metadata"
    static let version = 1
    static let maximumBytes = 16 * 1_024 * 1_024
    static let maximumRecords = 125_000

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    static func encode(
        library: TropLibraryBackupSnapshot,
        createdAt: Date = Date()
    ) throws -> Data {
        try validate(library)
        let payload = try encoder().encode(library)
        guard payload.count <= maximumBytes else { throw TropLibraryBackupError.tooLarge }
        let envelope = TropLibraryBackupEnvelope(
            format: format,
            schemaVersion: version,
            createdAt: createdAt,
            payloadSHA256: digest(payload),
            library: library
        )
        let data = try encoder().encode(envelope)
        guard data.count <= maximumBytes else { throw TropLibraryBackupError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> TropLibraryBackupEnvelope {
        guard data.count <= maximumBytes else { throw TropLibraryBackupError.tooLarge }
        let envelope: TropLibraryBackupEnvelope
        do {
            envelope = try decoder().decode(TropLibraryBackupEnvelope.self, from: data)
        } catch {
            throw TropLibraryBackupError.invalidPayload
        }
        guard envelope.format == format, envelope.schemaVersion == version else {
            throw TropLibraryBackupError.unsupportedFormat
        }
        try validate(envelope.library)
        let canonical = try encoder().encode(envelope.library)
        guard digest(canonical) == envelope.payloadSHA256 else {
            throw TropLibraryBackupError.checksumMismatch
        }
        return envelope
    }

    static func inspect(_ data: Data) throws -> TropLibraryBackupSummary {
        let envelope = try decode(data)
        let library = envelope.library
        let trackIDs = Set(library.tracks.map(\.id))
        let playlistIDs = Set(library.playlists.map(\.id))
        let unresolved = library.playlistEntries.filter {
            !trackIDs.contains($0.songId) || !playlistIDs.contains($0.playlistId)
        }.count
        return TropLibraryBackupSummary(
            createdAt: envelope.createdAt,
            tracks: library.tracks.count,
            likedSongs: library.tracks.filter(\.liked).count,
            albums: library.albums.count,
            artists: library.artists.count,
            playlists: library.playlists.filter { $0.bookmarkedAt != nil }.count,
            playlistEntries: library.playlistEntries.count,
            podcasts: library.podcasts.count,
            episodes: library.episodes.count,
            unresolvedEntries: unresolved
        )
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 512
            && !id.contains("://") && !id.contains("?") && !id.contains("#")
            && !id.hasPrefix("/") && !id.contains("\\")
            && !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func validText(_ text: String) -> Bool {
        text.utf8.count <= 2_048
            && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func validate(_ library: TropLibraryBackupSnapshot) throws {
        let counts = [
            library.tracks.count, library.albums.count, library.artists.count,
            library.playlists.count, library.playlistEntries.count,
            library.podcasts.count, library.episodes.count
        ]
        guard counts.reduce(0, +) <= maximumRecords,
              library.tracks.allSatisfy({
                  validID($0.id) && validText($0.title)
                      && $0.artistName.map(validText) != false
                      && $0.albumName.map(validText) != false
                      && $0.duration >= 0
              }),
              library.albums.allSatisfy({ validID($0.id) && validText($0.title) }),
              library.artists.allSatisfy({ validID($0.id) && validText($0.name) }),
              library.playlists.allSatisfy({
                  validID($0.id) && validText($0.name)
                      && $0.browseId.map(validID) != false
              }),
              library.playlistEntries.allSatisfy({
                  validID($0.playlistId) && validID($0.songId) && $0.position >= 0
              }),
              library.podcasts.allSatisfy({ validID($0.id) && validText($0.name) }),
              library.episodes.allSatisfy({
                  validID($0.id) && validText($0.title)
                      && $0.podcastId.map(validID) != false && $0.duration >= 0
              })
        else { throw TropLibraryBackupError.invalidPayload }
        guard Set(library.tracks.map(\.id)).count == library.tracks.count,
              Set(library.albums.map(\.id)).count == library.albums.count,
              Set(library.artists.map(\.id)).count == library.artists.count,
              Set(library.playlists.map(\.id)).count == library.playlists.count,
              Set(library.podcasts.map(\.id)).count == library.podcasts.count,
              Set(library.episodes.map(\.id)).count == library.episodes.count
        else { throw TropLibraryBackupError.invalidPayload }
    }
}
