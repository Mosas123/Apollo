import Foundation

/// A provider-independent catalogue object. Playback never uses these ids
/// directly: an audio provider resolves them to a stream later.
enum CatalogSource: String, Codable, Sendable {
    case spotify
    case youtube
    case addon
    case apple
    case musicBrainz
}

struct CatalogArtist: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let artworkURL: URL?
}

struct CatalogAlbumRef: Hashable, Sendable {
    let id: String
    let title: String
    let artworkURL: URL?
}

struct CatalogTrack: Identifiable, Hashable, Sendable {
    let id: String
    let source: CatalogSource
    let title: String
    let artists: [CatalogArtist]
    let album: CatalogAlbumRef?
    let durationMS: Int
    let isrc: String?
    let artworkURL: URL?
    let externalURL: URL?
    let isExplicit: Bool
}

struct CatalogAlbum: Identifiable, Hashable, Sendable {
    let id: String
    let source: CatalogSource
    let title: String
    let artists: [CatalogArtist]
    let releaseDate: String?
    let artworkURL: URL?
    let externalURL: URL?
}

struct CatalogPodcast: Identifiable, Hashable, Sendable {
    let id: String
    let source: CatalogSource
    let title: String
    let author: String?
    let artworkURL: URL?
    let externalURL: URL?
}

struct CatalogEpisode: Identifiable, Hashable, Sendable {
    let id: String
    let source: CatalogSource
    let title: String
    let showTitle: String?
    let durationMS: Int
    let releaseDate: String?
    let artworkURL: URL?
    let description: String?
    let externalURL: URL?
}

struct CatalogPlaylist: Identifiable, Hashable, Sendable {
    let id: String
    let source: CatalogSource
    let title: String
    let owner: String?
    let artworkURL: URL?
    let externalURL: URL?
}

struct CatalogSearchResults: Sendable {
    var tracks: [CatalogTrack] = []
    var albums: [CatalogAlbum] = []
    var artists: [CatalogArtist] = []
    var playlists: [CatalogPlaylist] = []
    var podcasts: [CatalogPodcast] = []
    var episodes: [CatalogEpisode] = []
    var audiobooks: [CatalogAlbum] = []

    var isEmpty: Bool {
        tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty
            && podcasts.isEmpty && episodes.isEmpty && audiobooks.isEmpty
    }
}

enum CatalogError: Error, Sendable {
    case unsupported
    case invalidResponse
    case notFound
    case http(Int)
    case authentication
}
