import Foundation

/// Catalogue identity is separate from YouTube's `videoId`.
/// Persist these keys rather than relying on a provider's raw ID being globally unique.
enum MusicCatalogSource: String, Codable, Hashable, Sendable {
    case youtube
    case audius
    case jamendo
}

struct MusicCatalogID: Codable, Hashable, Sendable {
    let source: MusicCatalogSource
    let rawValue: String

    var storageKey: String { "\(source.rawValue):\(rawValue)" }
}

/// Provider-agnostic search result. This intentionally does not conform to `SongItem`:
/// `SongItem.videoId` and the existing queue currently assume YouTube IDs.
struct MusicCatalogTrack: Hashable, Sendable {
    let id: MusicCatalogID
    let title: String
    let artist: String
    let durationSeconds: Int
    let artworkURL: URL?
    let permalinkURL: URL?
    let isStreamable: Bool
}

enum MusicCatalogError: Error, Equatable {
    case invalidURL
    case httpStatus(Int)
    case wrongProvider
    case unavailableTrack
}

/// A catalogue provider must supply a playable URL only for tracks permitted
/// for unauthenticated full-length streaming. The player owns the actual request.
protocol MusicCatalogProvider: Sendable {
    var source: MusicCatalogSource { get }
    func searchTracks(query: String, limit: Int) async throws -> [MusicCatalogTrack]
    func streamURL(for track: MusicCatalogTrack) throws -> URL
}
