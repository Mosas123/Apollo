import Foundation

enum SpotifyAuthError: Error, Sendable {
    case invalidResponse
    case http(Int)
    case missingToken
    case missingClientVersion
}

/// The anonymous Spotify web-player session: scrape the client version and
/// `sp_t` cookie, mint a TOTP access token, exchange it for a Client-Token,
/// and reuse the triple until a query answers 401.
actor SpotifyAnonymousSession {
    static let shared = SpotifyAnonymousSession()

    struct Tokens: Sendable {
        let accessToken: String
        let clientToken: String
        let clientVersion: String
    }

    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"

    private let session: URLSession
    private var cached: Tokens?
    private var inflight: Task<Tokens, Error>?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept-Language": "en-US,en;q=0.9"
        ]
        session = URLSession(configuration: configuration)
    }

    func current() async throws -> Tokens {
        if let cached { return cached }
        if let inflight { return try await inflight.value }

        let task = Task { try await self.mint() }
        inflight = task
        do {
            let tokens = try await task.value
            cached = tokens
            inflight = nil
            return tokens
        } catch {
            inflight = nil
            throw error
        }
    }

    func refresh() async throws -> Tokens {
        cached = nil
        inflight = nil
        return try await current()
    }

    // MARK: - Mint

    private func mint() async throws -> Tokens {
        let homeURL = URL(string: "https://open.spotify.com")!
        var homeRequest = URLRequest(url: homeURL)
        homeRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (homeData, homeResponse) = try await session.data(for: homeRequest)
        guard let homeHTTP = homeResponse as? HTTPURLResponse else {
            throw SpotifyAuthError.invalidResponse
        }
        guard homeHTTP.statusCode == 200 else {
            throw SpotifyAuthError.http(homeHTTP.statusCode)
        }

        let html = String(data: homeData, encoding: .utf8) ?? ""
        let clientVersion = extractClientVersion(from: html)
        guard !clientVersion.isEmpty else {
            throw SpotifyAuthError.missingClientVersion
        }

        let deviceId = cookieValue(named: "sp_t", for: homeURL)
            ?? setCookieValue(named: "sp_t", in: homeHTTP)

        guard let totp = await SpotifyTOTP.code() else {
            throw SpotifyAuthError.missingToken
        }

        var components = URLComponents(string: "https://open.spotify.com/api/token")!
        components.queryItems = [
            URLQueryItem(name: "reason", value: "init"),
            URLQueryItem(name: "productType", value: "web-player"),
            URLQueryItem(name: "totp", value: totp.code),
            URLQueryItem(name: "totpVer", value: String(totp.version)),
            URLQueryItem(name: "totpServer", value: totp.code)
        ]

        var tokenRequest = URLRequest(url: components.url!)
        tokenRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        tokenRequest.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let (tokenData, tokenResponse) = try await session.data(for: tokenRequest)
        guard let tokenHTTP = tokenResponse as? HTTPURLResponse else {
            throw SpotifyAuthError.invalidResponse
        }
        guard tokenHTTP.statusCode == 200 else {
            throw SpotifyAuthError.http(tokenHTTP.statusCode)
        }

        guard let tokenJSON = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let accessToken = tokenJSON["accessToken"] as? String,
              !accessToken.isEmpty,
              let clientId = tokenJSON["clientId"] as? String,
              !clientId.isEmpty else {
            throw SpotifyAuthError.missingToken
        }

        let clientToken = try await fetchClientToken(
            clientId: clientId,
            deviceId: deviceId,
            clientVersion: clientVersion
        )

        return Tokens(
            accessToken: accessToken,
            clientToken: clientToken,
            clientVersion: clientVersion
        )
    }

    private func fetchClientToken(
        clientId: String,
        deviceId: String,
        clientVersion: String
    ) async throws -> String {
        let payload: [String: Any] = [
            "client_data": [
                "client_version": clientVersion,
                "client_id": clientId,
                "js_sdk_data": [
                    "device_brand": "unknown",
                    "device_model": "unknown",
                    "os": "windows",
                    "os_version": "NT 10.0",
                    "device_id": deviceId,
                    "device_type": "computer"
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://clienttoken.spotify.com/v1/clienttoken")!)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAuthError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw SpotifyAuthError.http(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["response_type"] as? String == "RESPONSE_GRANTED_TOKEN_RESPONSE",
              let granted = json["granted_token"] as? [String: Any],
              let token = granted["token"] as? String,
              !token.isEmpty else {
            throw SpotifyAuthError.missingToken
        }
        return token
    }

    // MARK: - HTML / cookies

    private func extractClientVersion(from html: String) -> String {
        if let encoded = firstMatch(
            in: html,
            pattern: #"<script[^>]+id=["']appServerConfig["'][^>]*>([^<]+)</script>"#
        ) {
            let cleaned = encoded.components(separatedBy: .whitespacesAndNewlines).joined()
            if let data = Data(base64Encoded: cleaned),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = json["clientVersion"] as? String,
               !version.isEmpty {
                return version
            }
        }

        return firstMatch(
            in: html,
            pattern: #""clientVersion"\s*:\s*"([^"]+)""#
        ) ?? ""
    }

    private func cookieValue(named name: String, for url: URL) -> String? {
        HTTPCookieStorage.shared.cookies(for: url)?
            .first(where: { $0.name == name })?
            .value
    }

    private func setCookieValue(named name: String, in response: HTTPURLResponse) -> String {
        let header = response.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        return firstMatch(in: header, pattern: "\(name)=([^;]+)") ?? ""
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[matchRange])
    }
}
