import Foundation

/// Spotify as a catalogue source. Search only for now; track/album/artist/
/// playlist detail and home feed land in the next phase on top of the same
/// Pathfinder client.
struct SpotifyCatalogProvider: CatalogSearching {
    let source: CatalogSource = .spotify

    private let client: SpotifyPathfinderClient

    init(client: SpotifyPathfinderClient = SpotifyPathfinderClient()) {
        self.client = client
    }

    func search(_ query: String, limit: Int = 20) async throws -> CatalogSearchResults {
        let data = try await client.search(query: query, limit: limit)
        return try Self.parseSearch(data, limit: limit)
    }

    // MARK: - Parsing

    private static func parseSearch(_ data: Data, limit: Int) throws -> CatalogSearchResults {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let search = payload["searchV2"] as? [String: Any] else {
            throw CatalogError.invalidResponse
        }

        var results = CatalogSearchResults()
        results.tracks = trackItems(search["tracksV2"] ?? search["tracks"], limit: limit)
        results.albums = albumItems(search["albumsV2"] ?? search["albums"], limit: limit)
        results.artists = artistItems(search["artistsV2"] ?? search["artists"], limit: limit)
        results.playlists = playlistItems(search["playlistsV2"] ?? search["playlists"], limit: limit)
        return results
    }

    private static func trackItems(_ node: Any?, limit: Int) -> [CatalogTrack] {
        items(from: node).prefix(limit).compactMap { wrapper in
            guard let data = dataNode(from: wrapper), let id = identifier(from: data) else { return nil }

            let albumNode = data["albumOfTrack"] as? [String: Any]
            let albumArtists = artists(from: albumNode?["artists"])
            let trackArtists = artists(from: data["artists"])
            let artists = trackArtists.isEmpty ? albumArtists : trackArtists

            let album = albumNode.flatMap { node -> CatalogAlbumRef? in
                guard let albumID = identifier(from: node),
                      let title = node["name"] as? String,
                      !title.isEmpty else { return nil }
                return CatalogAlbumRef(
                    id: albumID,
                    title: title,
                    artworkURL: coverURL(from: node["coverArt"])
                )
            }

            let title = (data["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
            let duration = milliseconds(from: (data["duration"] as? [String: Any])?["totalMilliseconds"])

            return CatalogTrack(
                id: id,
                source: .spotify,
                title: title,
                artists: artists,
                album: album,
                durationMS: duration,
                isrc: nil,
                artworkURL: coverURL(from: albumNode?["coverArt"]),
                externalURL: URL(string: "https://open.spotify.com/track/\(id)"),
                isExplicit: (data["contentRating"] as? [String: Any])?["label"] as? String == "EXPLICIT"
            )
        }
    }

    private static func albumItems(_ node: Any?, limit: Int) -> [CatalogAlbum] {
        items(from: node).prefix(limit).compactMap { wrapper in
            guard let data = dataNode(from: wrapper), let id = identifier(from: data) else { return nil }
            let title = (data["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
            return CatalogAlbum(
                id: id,
                source: .spotify,
                title: title,
                artists: artists(from: data["artists"]),
                releaseDate: (data["date"] as? [String: Any])?["isoString"] as? String,
                artworkURL: coverURL(from: data["coverArt"]),
                externalURL: URL(string: "https://open.spotify.com/album/\(id)")
            )
        }
    }

    private static func artistItems(_ node: Any?, limit: Int) -> [CatalogArtist] {
        items(from: node).prefix(limit).compactMap { wrapper in
            guard let data = dataNode(from: wrapper), let id = identifier(from: data) else { return nil }
            let name = ((data["profile"] as? [String: Any])?["name"] as? String)
                ?? (data["name"] as? String)
                ?? "Unknown"
            return CatalogArtist(
                id: id,
                name: name,
                artworkURL: coverURL(from: data["visualIdentity"])
                    ?? coverURL(from: (data["visuals"] as? [String: Any])?["avatarImage"])
            )
        }
    }

    private static func playlistItems(_ node: Any?, limit: Int) -> [CatalogPlaylist] {
        items(from: node).prefix(limit).compactMap { wrapper in
            guard let data = dataNode(from: wrapper), let id = identifier(from: data) else { return nil }
            let ownerNode = (data["ownerV2"] as? [String: Any])?["data"] as? [String: Any]
                ?? (data["owner"] as? [String: Any])
            let owner = (ownerNode?["displayName"] as? String) ?? (ownerNode?["name"] as? String)
            let title = (data["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
            return CatalogPlaylist(
                id: id,
                source: .spotify,
                title: title,
                owner: owner,
                artworkURL: coverURL(from: data["images"]),
                externalURL: URL(string: "https://open.spotify.com/playlist/\(id)")
            )
        }
    }

    // MARK: - Graph shapes

    private static func items(from node: Any?) -> [[String: Any]] {
        guard let dict = node as? [String: Any] else { return [] }
        return (dict["items"] as? [[String: Any]]) ?? []
    }

    private static func dataNode(from wrapper: [String: Any]) -> [String: Any]? {
        if let nested = (wrapper["item"] as? [String: Any])?["data"] as? [String: Any] {
            return nested
        }
        return wrapper["data"] as? [String: Any]
    }

    private static func identifier(from node: [String: Any]) -> String? {
        if let id = node["id"] as? String, !id.isEmpty { return id }
        if let uri = node["uri"] as? String, let last = uri.split(separator: ":").last {
            return String(last)
        }
        return nil
    }

    private static func artists(from node: Any?) -> [CatalogArtist] {
        guard let dict = node as? [String: Any],
              let items = dict["items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            let profile = item["profile"] as? [String: Any]
            let name = (profile?["name"] as? String) ?? (item["name"] as? String)
            guard let id = identifier(from: item), let name, !name.isEmpty else { return nil }
            return CatalogArtist(
                id: id,
                name: name,
                artworkURL: coverURL(from: profile?["visualIdentity"])
                    ?? coverURL(from: item["visualIdentity"])
            )
        }
    }

    private static func coverURL(from node: Any?) -> URL? {
        guard let dict = node as? [String: Any] else { return nil }

        var sources = dict["sources"] as? [[String: Any]] ?? []
        if sources.isEmpty,
           let image = dict["image"] as? [String: Any],
           let nested = image["data"] as? [String: Any],
           let imageSources = nested["sources"] as? [[String: Any]] {
            sources = imageSources
        }

        let candidates = sources.compactMap { source -> (Int, URL)? in
            guard let raw = source["url"] as? String,
                  let url = URL(string: raw) else { return nil }
            let width = max(milliseconds(from: source["width"]), milliseconds(from: source["maxWidth"]))
            return (width, url)
        }

        return candidates.max { $0.0 < $1.0 }?.1
    }

    private static func milliseconds(from value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
}
