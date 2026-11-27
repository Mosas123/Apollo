import Foundation

/// Thin transport for Spotify's web-player Pathfinder GraphQL. The persisted
/// query hashes are the same ones the web player ships; when Spotify rotates
/// them this is the one place to update.
struct SpotifyPathfinderClient: @unchecked Sendable {
    private static let endpoint = URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!
    private static let searchHash = "fcad5a3e0d5af727fb76966f06971c19cfa2275e6ff7671196753e008611873c"
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
