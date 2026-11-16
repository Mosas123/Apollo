import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Lightweight, deterministic checks without iOS/Xcode dependencies.
@main
struct AudiusClientChecks {
    static func main() async throws {
        let payload = """
        {
          "data": [
            {
              "id": "audius123", "title": "Free Track", "duration": 183,
              "user": { "name": "Example Artist" },
              "artwork": { "480x480": "https://example.org/cover.jpg" },
              "permalink": "/example/free-track", "is_streamable": true,
              "is_stream_gated": false, "is_available": true
            },
            { "id": "paid", "title": "Paid", "is_streamable": false },
            { "id": "gated", "title": "Gated", "is_streamable": true, "is_stream_gated": true },
            { "id": "removed", "title": "Removed", "is_streamable": true, "is_available": false }
          ]
        }
        """
        let client = AudiusClient { request in
            guard let url = request.url else { throw MusicCatalogError.invalidURL }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)
            precondition(query?.queryItems?.first(where: { $0.name == "query" })?.value == "canción & jazz")
            precondition(query?.queryItems?.first(where: { $0.name == "limit" })?.value == "50")
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                throw MusicCatalogError.invalidURL
            }
            return (Data(payload.utf8), response)
        }
        let tracks = try await client.searchTracks(query: " canción & jazz ", limit: 500)
        precondition(tracks.count == 1, "Only freely streamable tracks should be shown")
        let track = tracks[0]
        precondition(track.title == "Free Track" && track.artist == "Example Artist")
        precondition(track.durationSeconds == 183)
        precondition(track.artworkURL?.absoluteString == "https://example.org/cover.jpg")
        precondition(track.permalinkURL?.absoluteString == "https://audius.co/example/free-track")
        precondition(track.id.storageKey == "audius:audius123")
        precondition(MusicCatalogID(storageKey: track.id.storageKey) == track.id)
        precondition(MusicCatalogID(storageKey: "D7KyD") == nil)
        precondition(MusicCatalogID(storageKey: "audius:") == nil)
        precondition(MusicPlaybackIdentity.isAudius(track.id.storageKey))
        precondition(!MusicPlaybackIdentity.isYouTube(track.id.storageKey))
        precondition(MusicPlaybackIdentity.isYouTube("someYouTubeID"))
        precondition(!MusicPlaybackIdentity.isYouTube("radio:uuid"))
        let streamURL = try client.streamURL(for: track)
        precondition(streamURL.absoluteString == "https://api.audius.co/v1/tracks/audius123/stream")
        precondition(MusicCatalogID(source: .youtube, rawValue: "audius123") != track.id)
        let emptyResults = try await client.searchTracks(query: "  ")
        precondition(emptyResults.isEmpty)

        let failures = AudiusClient { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: nil) else {
                throw MusicCatalogError.invalidURL
            }
            return (Data(), response)
        }
        do {
            _ = try await failures.searchTracks(query: "song")
            preconditionFailure("429 should be propagated")
        } catch MusicCatalogError.httpStatus(let code) {
            precondition(code == 429)
        }
        let invalid = MusicCatalogTrack(
            id: MusicCatalogID(source: .youtube, rawValue: "abc"),
            title: "Other", artist: "Artist", durationSeconds: 100,
            artworkURL: nil, permalinkURL: nil, isStreamable: true
        )
        do {
            _ = try client.streamURL(for: invalid)
            preconditionFailure("YouTube IDs must not be resolved as Audius")
        } catch MusicCatalogError.wrongProvider {}
        print("Audius client checks passed")
    }
}
