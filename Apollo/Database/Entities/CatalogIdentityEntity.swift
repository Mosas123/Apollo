import Foundation
import GRDB

/// Persisted identity/enrichment for a canonical recording. It is deliberately
/// small: the full catalogue payload is still rebuilt by the active provider.
struct CatalogIdentityEntity: Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    var id: String
    var source: String
    var title: String
    var artistNames: String?
    var albumTitle: String?
    var durationMS: Int
    var isrc: String?
    var mbid: String?
    var artworkURL: String?
    var genre: String?
    var releaseDate: String?
    var spotifyID: String?
    var youtubeID: String?
    var updatedAt: Date

    static let databaseTableName = "catalog_identity"

    enum CodingKeys: String, CodingKey {
        case id, source, title, isrc, mbid, genre
        case artistNames = "artist_names"
        case albumTitle = "album_title"
        case durationMS = "duration_ms"
        case artworkURL = "artwork_url"
        case releaseDate = "release_date"
        case spotifyID = "spotify_id"
        case youtubeID = "youtube_id"
        case updatedAt = "updated_at"
    }

    var enrichment: CatalogEnrichment {
        CatalogEnrichment(
            artworkURL: artworkURL.flatMap(URL.init(string:)),
            artworkSource: artworkURL == nil ? nil : .apple,
            genre: genre,
            genreSource: genre == nil ? nil : .apple,
            releaseDate: releaseDate,
            releaseDateSource: releaseDate == nil ? nil : .apple,
            isrc: isrc,
            mbid: mbid
        )
    }
}
