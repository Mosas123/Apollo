import Foundation

/// Thin transport for Spotify's web-player Pathfinder GraphQL. The persisted
/// query hashes are the same ones the web player ships; when Spotify rotates
/// them this is the one place to update.
struct SpotifyPathfinderClient: @unchecked Sendable {
    private static let endpoint = URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!
    private static let searchHash = "fcad5a3e0d5af727fb76966f06971c19cfa2275e6ff7671196753e008611873c"
    private static let albumHash = "b9bfabef66ed756e5e13f68a942deb60bd4125ec1f1be8cc42769dc0259b4b10"
    private static let playlistHash = "bb67e0af06e8d6f52b531f97468ee4acd44cd0f82b988e15c2ea47b1148efc77"
    private static let artistOverviewHash = "446130b4a0aa6522a686aafccddb0ae849165b5e0436fd802f96e0243617b5d8"
    private static let artistDiscographyHash = "5e07d323febb57b4a56a42abbf781490e58764aa45feb6e3dc0591564fc56599"
    private static let trackHash = "612585ae06ba435ad26369870deaae23b5c8800a256cd8a57e08eddc25a37294"
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"

    private let auth: SpotifyAnonymousSession
    private let session: URLSession

    init(auth: SpotifyAnonymousSession = .shared) {
        self.auth = auth
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: configuration)
    }

    func search(query: String, limit: Int) async throws -> Data {
        let variables: [String: Any] = [
            "searchTerm": query,
            "offset": 0,
            "limit": max(1, limit),
            "numberOfTopResults": 5,
            "includeAudiobooks": true,
            "includeArtistHasConcertsField": false,
            "includePreReleases": true,
            "includeAuthors": false
        ]
        return try await perform(
            operationName: "searchDesktop",
            variables: variables,
            hash: Self.searchHash
        )
    }

    func album(id: String) async throws -> Data {
        try await perform(
            operationName: "getAlbum",
            variables: [
                "uri": "spotify:album:\(id)",
                "locale": "",
                "offset": 0,
                "limit": 100
            ],
            hash: Self.albumHash
        )
    }

    func playlist(id: String, offset: Int = 0, limit: Int = 100) async throws -> Data {
        try await perform(
            operationName: "fetchPlaylist",
            variables: [
                "uri": "spotify:playlist:\(id)",
                "offset": offset,
                "limit": limit,
                "enableWatchFeedEntrypoint": false
            ],
            hash: Self.playlistHash
        )
    }

    func artistOverview(id: String) async throws -> Data {
        try await perform(
            operationName: "queryArtistOverview",
            variables: ["uri": "spotify:artist:\(id)", "locale": ""],
            hash: Self.artistOverviewHash
        )
    }

    func artistDiscography(id: String, offset: Int = 0, limit: Int = 50) async throws -> Data {
        try await perform(
            operationName: "queryArtistDiscographyAll",
            variables: [
                "uri": "spotify:artist:\(id)",
                "offset": offset,
                "limit": limit,
                "order": "DATE_DESC"
            ],
            hash: Self.artistDiscographyHash
        )
    }

    func track(id: String) async throws -> Data {
        try await perform(
            operationName: "getTrack",
            variables: ["uri": "spotify:track:\(id)"],
            hash: Self.trackHash
        )
    }

    private func perform(
        operationName: String,
        variables: [String: Any],
        hash: String
    ) async throws -> Data {
        let payload: [String: Any] = [
            "operationName": operationName,
            "variables": variables,
            "extensions": ["persistedQuery": ["version": 1, "sha256Hash": hash]]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        for attempt in 0..<2 {
            let tokens = try await auth.current()
            var request = URLRequest(url: Self.endpoint)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(tokens.clientToken, forHTTPHeaderField: "Client-Token")
            request.setValue(tokens.clientVersion, forHTTPHeaderField: "Spotify-App-Version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CatalogError.invalidResponse
            }

            if http.statusCode == 401, attempt == 0 {
                _ = try await auth.refresh()
                continue
            }
            guard http.statusCode == 200 else {
                throw CatalogError.http(http.statusCode)
            }
            return data
        }

        throw CatalogError.authentication
    }
}
