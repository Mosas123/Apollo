import Foundation

/// Spotify's editorial home feed, projected into the same `HomePage.Section`
/// model the Home screen already renders.
@MainActor
final class SpotifyHomeService {
    static let shared = SpotifyHomeService()

    private let client: SpotifyPathfinderClient

    init(client: SpotifyPathfinderClient = SpotifyPathfinderClient()) {
        self.client = client
    }

    func sections() async throws -> [HomePage.Section] {
        let data = try await client.home(timeZone: TimeZone.current.identifier)
        return try Self.parse(data)
    }

    private static func parse(_ data: Data) throws -> [HomePage.Section] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let home = payload["home"] as? [String: Any],
              let container = home["sectionContainer"] as? [String: Any],
              let sectionGroup = container["sections"] as? [String: Any],
              let sectionItems = sectionGroup["items"] as? [[String: Any]] else {
            throw CatalogError.notFound
        }

        var result: [HomePage.Section] = []

        for section in sectionItems {
            let sectionData = section["data"] as? [String: Any]
            let title = ((sectionData?["title"] as? [String: Any])?["text"] as? String)
                ?? (sectionData?["title"] as? String)
                ?? ""
            guard !title.isEmpty else { continue }

            let rawItems = ((section["sectionItems"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
            var mapped: [YTItem] = []
            var seen = Set<String>()

            for rawItem in rawItems {
                guard let content = ((rawItem["content"] as? [String: Any])?["data"] as? [String: Any]),
                      let uri = content["uri"] as? String else { continue }
                let parts = uri.split(separator: ":")
                guard parts.count >= 3 else { continue }
                let type = String(parts[1])
                let fallbackID = String(parts[2])

                let item: YTItem?
                switch type {
                case "track":
                    item = trackItem(from: content, fallbackID: fallbackID)
                case "album":
                    item = albumItem(from: content, fallbackID: fallbackID)
                case "playlist":
                    item = playlistItem(from: content, fallbackID: fallbackID)
                case "artist":
                    item = artistItem(from: content, fallbackID: fallbackID)
                default:
                    item = nil
                }

                guard let item, seen.insert(item.id).inserted else { continue }
                mapped.append(item)
            }

            if !mapped.isEmpty {
                result.append(HomePage.Section(title: title, items: mapped))
            }
        }

        return result
    }

    private static func trackItem(from node: [String: Any], fallbackID: String) -> YTItem? {
        let trackID = identifier(node) ?? fallbackID
        guard !trackID.isEmpty else { return nil }
        let title = (node["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        let albumNode = node["albumOfTrack"] as? [String: Any]
        let durationMS = intValue((node["duration"] as? [String: Any])?["totalMilliseconds"])
        let cover = coverURL(from: albumNode?["coverArt"]) ?? coverURL(from: node["coverArt"])
        let albumID = albumNode.flatMap(identifier)
        let albumTitle = albumNode?["name"] as? String
        let album = albumID.flatMap { id in
            albumTitle.map {
                CatalogAlbumRef(id: id, title: $0, artworkURL: coverURL(from: albumNode?["coverArt"]))
            }
        }

        let track = CatalogTrack(
            id: trackID,
            source: .spotify,
            title: title,
            artists: artists(from: node["artists"]),
            album: album,
            durationMS: durationMS,
            isrc: nil,
            artworkURL: cover,
            externalURL: URL(string: "https://open.spotify.com/track/\(trackID)"),
            isExplicit: (node["contentRating"] as? [String: Any])?["label"] as? String == "EXPLICIT"
        )
        return .song(SpotifyCatalogMapper.song(from: track))
    }

    private static func albumItem(from node: [String: Any], fallbackID: String) -> YTItem? {
        let albumID = identifier(node) ?? fallbackID
        guard !albumID.isEmpty else { return nil }
        let title = (node["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        let album = CatalogAlbum(
            id: albumID,
            source: .spotify,
            title: title,
            artists: artists(from: node["artists"]),
            releaseDate: yearDate(from: node["date"]),
            artworkURL: coverURL(from: node["coverArt"]),
            externalURL: URL(string: "https://open.spotify.com/album/\(albumID)")
        )
        return .album(SpotifyCatalogMapper.album(from: album))
    }

    private static func playlistItem(from node: [String: Any], fallbackID: String) -> YTItem? {
        let playlistID = identifier(node) ?? fallbackID
        guard !playlistID.isEmpty else { return nil }
        let title = (node["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        let owner = ((node["ownerV2"] as? [String: Any])?["data"] as? [String: Any])
        let playlist = CatalogPlaylist(
            id: playlistID,
            source: .spotify,
            title: title,
            owner: (owner?["name"] as? String) ?? (owner?["username"] as? String),
            artworkURL: coverURL(from: node["images"]),
            externalURL: URL(string: "https://open.spotify.com/playlist/\(playlistID)")
        )
        return .playlist(SpotifyCatalogMapper.playlist(from: playlist))
    }

    private static func artistItem(from node: [String: Any], fallbackID: String) -> YTItem? {
        let artistID = identifier(node) ?? fallbackID
        guard !artistID.isEmpty else { return nil }
        let name = ((node["profile"] as? [String: Any])?["name"] as? String)
            ?? (node["name"] as? String)
            ?? "Unknown"
        let avatar = coverURL(from: (node["visuals"] as? [String: Any])?["avatarImage"])
            ?? coverURL(from: node["visualIdentity"])
        let artist = CatalogArtist(id: artistID, name: name, artworkURL: avatar)
        return .artist(SpotifyCatalogMapper.artist(from: artist))
    }

    // MARK: - JSON helpers

    private static func identifier(_ node: [String: Any]) -> String? {
        if let id = node["id"] as? String, !id.isEmpty { return id }
        if let uri = node["uri"] as? String, let last = uri.split(separator: ":").last {
            return String(last)
        }
        return nil
    }

    private static func artists(from node: Any?) -> [CatalogArtist] {
        guard let dict = node as? [String: Any],
              let entries = dict["items"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            let profile = entry["profile"] as? [String: Any]
            guard let name = (profile?["name"] as? String) ?? (entry["name"] as? String),
                  !name.isEmpty,
                  let id = identifier(entry) else { return nil }
            let avatar = coverURL(from: (profile?["visualIdentity"] ?? entry["visualIdentity"]))
            return CatalogArtist(id: id, name: name, artworkURL: avatar)
        }
    }

    private static func coverURL(from node: Any?) -> URL? {
        guard let dict = node as? [String: Any] else { return nil }
        var sources = dict["sources"] as? [[String: Any]] ?? []
        if sources.isEmpty,
           let data = dict["data"] as? [String: Any],
           let nested = data["sources"] as? [[String: Any]] {
            sources = nested
        }
        if sources.isEmpty,
           let image = dict["image"] as? [String: Any],
           let data = image["data"] as? [String: Any],
           let nested = data["sources"] as? [[String: Any]] {
            sources = nested
        }
        if sources.isEmpty,
           let images = dict["items"] as? [[String: Any]] {
            sources = images.flatMap { $0["sources"] as? [[String: Any]] ?? [] }
        }
        let candidates = sources.compactMap { source -> (Int, URL)? in
            guard let raw = source["url"] as? String, let url = URL(string: raw) else { return nil }
            return (max(intValue(source["width"]), intValue(source["maxWidth"])), url)
        }
        return candidates.max { $0.0 < $1.0 }?.1
    }

    private static func yearDate(from node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        return dict["isoString"] as? String
    }

    private static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
}
