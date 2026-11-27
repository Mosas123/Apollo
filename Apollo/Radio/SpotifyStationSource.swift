import Foundation

struct SpotifyStationSnapshot: Sendable {
    let artist: CatalogArtist
    let topTracks: [SongItem]
    let related: [CatalogArtist]
}

/// Reads only the fields the station engine needs from `queryArtistOverview`:
/// top tracks and related artists. It deliberately skips the discography call.
struct SpotifyStationSource: @unchecked Sendable {
    private let client = SpotifyPathfinderClient()

    func snapshot(artistID: String) async throws -> SpotifyStationSnapshot {
        let data = try await client.artistOverview(id: artistID)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let artist = payload["artistUnion"] as? [String: Any] else {
            throw CatalogError.notFound
        }

        let profile = artist["profile"] as? [String: Any]
        let name = (profile?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        let avatar = coverURL(from: (artist["visuals"] as? [String: Any])?["avatarImage"])
            ?? coverURL(from: artist["visualIdentity"])
        let catalogArtist = CatalogArtist(
            id: artistID,
            name: name,
            artworkURL: avatar
        )

        let topTracks = items(of: (artist["discography"] as? [String: Any])?["topTracks"])
            .compactMap { wrapper -> SongItem? in
                let track = (wrapper["track"] as? [String: Any]) ?? wrapper
                return song(from: track, fallbackArtist: catalogArtist)
            }

        let related = items(of: ((artist["relatedContent"] as? [String: Any])?["relatedArtists"]))
            .compactMap { node -> CatalogArtist? in
                guard let id = identifier(node),
                      let profile = node["profile"] as? [String: Any],
                      let name = profile["name"] as? String,
                      !name.isEmpty else { return nil }
                return CatalogArtist(
                    id: id,
                    name: name,
                    artworkURL: coverURL(from: (node["visuals"] as? [String: Any])?["avatarImage"])
                )
            }

        return SpotifyStationSnapshot(artist: catalogArtist, topTracks: topTracks, related: related)
    }

    private func song(from track: [String: Any], fallbackArtist: CatalogArtist) -> SongItem? {
        guard let trackID = identifier(track) else { return nil }
        let title = (track["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        let albumNode = track["albumOfTrack"] as? [String: Any]
        let trackArtists = artists(from: track["artists"])
        let durationMS = intValue((track["duration"] as? [String: Any])?["totalMilliseconds"])
        let cover = coverURL(from: albumNode?["coverArt"])?.absoluteString
        let albumID = albumNode.flatMap(identifier)

        return SongItem(
            videoId: SpotifyCatalogID.track(trackID),
            title: title,
            artists: trackArtists.isEmpty
                ? [YTArtist(name: fallbackArtist.name, id: SpotifyCatalogID.artist(fallbackArtist.id))]
                : trackArtists.map { YTArtist(name: $0.name, id: SpotifyCatalogID.artist($0.id)) },
            album: albumNode?["name"] as? String,
            albumId: albumID.map(SpotifyCatalogID.album),
            duration: max(0, durationMS / 1000),
            thumbnailUrl: cover,
            isExplicit: (track["contentRating"] as? [String: Any])?["label"] as? String == "EXPLICIT",
            playlistId: nil,
            viewCount: nil,
            year: nil,
            isVideo: false,
            musicVideoType: nil,
            recordingPreference: .albumAudio,
            contentKind: .music,
            catalogID: SpotifyCatalogID.track(trackID)
        )
    }

    private func artists(from node: Any?) -> [CatalogArtist] {
        guard let dict = node as? [String: Any],
              let entries = dict["items"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            let profile = entry["profile"] as? [String: Any]
            guard let id = identifier(entry),
                  let name = (profile?["name"] as? String) ?? (entry["name"] as? String),
                  !name.isEmpty else { return nil }
            return CatalogArtist(id: id, name: name, artworkURL: nil)
        }
    }

    private func identifier(_ node: [String: Any]) -> String? {
        if let id = node["id"] as? String, !id.isEmpty { return id }
        if let uri = node["uri"] as? String, let last = uri.split(separator: ":").last {
            return String(last)
        }
        return nil
    }

    private func items(of node: Any?) -> [[String: Any]] {
        guard let dict = node as? [String: Any] else { return [] }
        return (dict["items"] as? [[String: Any]]) ?? []
    }

    private func coverURL(from node: Any?) -> URL? {
        guard let dict = node as? [String: Any] else { return nil }
        var sources = dict["sources"] as? [[String: Any]] ?? []
        if sources.isEmpty,
           let data = dict["data"] as? [String: Any],
           let nested = data["sources"] as? [[String: Any]] {
            sources = nested
        }
        let candidates = sources.compactMap { source -> (Int, URL)? in
            guard let raw = source["url"] as? String, let url = URL(string: raw) else { return nil }
            return (max(intValue(source["width"]), intValue(source["maxWidth"])), url)
        }
        return candidates.max { $0.0 < $1.0 }?.1
    }

    private func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
}
