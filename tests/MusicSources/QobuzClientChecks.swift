import Foundation

@main
struct QobuzClientChecks {
    static func main() async throws {
        let credentials = QobuzCredentials(
            appId: "123456789", appSecret: "test-secret", userAuthToken: "test-user-token"
        )
        let searchResponse = """
        {"tracks":{"items":[
            {"id":1234,"title":"Full FLAC","duration":225,"streamable":true,
             "performer":{"name":"Example Artist"},
             "album":{"image":{"large":"https://example.org/art.jpg"}}},
            {"id":5678,"title":"Unavailable","streamable":false}
        ]}}
        """
        let fileResponse = """
        {"url":"https://cdn.example.org/authorized/full.flac","format_id":6,
         "sample":false,"file_type":"full","restrictions":[]}
        """
        let client = QobuzClient(
            transport: { request in
                guard let url = request.url,
                      let response = HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: nil, headerFields: nil
                      ) else { throw QobuzError.invalidURL }
                precondition(request.value(forHTTPHeaderField: "X-App-Id") == credentials.appId)
                precondition(request.value(forHTTPHeaderField: "X-User-Auth-Token") == credentials.userAuthToken)
                precondition(!url.absoluteString.contains(credentials.appSecret))
                let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let values = (parts?.queryItems ?? []).reduce(into: [String: String]()) { map, item in
                    map[item.name] = item.value
                }
                precondition(values["app_id"] == credentials.appId)
                if url.path.hasSuffix("/catalog/search") {
                    precondition(values["query"] == "canción & jazz")
                    precondition(values["limit"] == "50")
                    return (Data(searchResponse.utf8), response)
                }
                precondition(url.path.hasSuffix("/track/getFileUrl"))
                precondition(values["track_id"] == "1234")
                precondition(values["format_id"] == "6")
                precondition(values["request_ts"] == "1700000000")
                precondition(values["request_sig"] == "22b46386bd4418518a673b3b51b364b9")
                return (Data(fileResponse.utf8), response)
            },
            clock: { 1_700_000_000 }
        )
        let tracks = try await client.searchTracks(
            query: " canción & jazz ", limit: 500, credentials: credentials
        )
        precondition(tracks.count == 1)
        precondition(tracks[0].id.storageKey == "qobuz:1234")
        precondition(tracks[0].title == "Full FLAC")
        precondition(tracks[0].artist == "Example Artist")
        precondition(tracks[0].artworkURL?.host == "example.org")
        let url = try await client.streamURL(trackId: "1234", credentials: credentials)
        precondition(url.absoluteString == "https://cdn.example.org/authorized/full.flac")

        let sampleClient = QobuzClient(
            transport: { request in
                guard let url = request.url,
                      let response = HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: nil, headerFields: nil
                      ) else { throw QobuzError.invalidURL }
                return (Data(#"{"url":"https://cdn.example.org/sample.mp3","format_id":5,"sample":true}"#.utf8), response)
            }
        )
        do {
            _ = try await sampleClient.streamURL(trackId: "1234", credentials: credentials)
            preconditionFailure("A preview must not be advertised as full length")
        } catch QobuzError.unavailableTrack {}
        do {
            _ = try await client.streamURL(trackId: "not-a-numeric-id", credentials: credentials)
            preconditionFailure("Reject non-numeric Qobuz IDs")
        } catch QobuzError.invalidTrack {}

        precondition(MusicCatalogID(storageKey: "qobuz:1234")?.source == .qobuz)
        precondition(MusicPlaybackIdentity.isQobuz("qobuz:1234"))
        precondition(!MusicPlaybackIdentity.isYouTube("qobuz:1234"))
        print("Qobuz client checks passed")
    }
}
