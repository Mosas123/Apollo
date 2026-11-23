import CommonCrypto
import Foundation

enum JioSaavnError: Error, Equatable {
    case badResponse
    case noStream
    case decryptFailed
}

/// JioSaavn catalogue + stream client, matching the reference client's calls:
///
///   GET api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=android&q=…&p=1&n=…
///   GET api.php?__call=song.getDetails&_format=json&_marker=0&api_version=4&ctx=android&pids=…
///
/// Streams come from `more_info.encrypted_media_url`, DES/ECB decrypted with a
/// fixed key, then optionally bumped to the 320 kbps variant.
struct JioSaavnClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let base = "https://www.jiosaavn.com/api.php"
    private let transport: Transport

    init(transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.transport = transport
    }

    func search(query: String, limit: Int = 25) async throws -> [MusicCatalogTrack] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        guard var comps = URLComponents(string: Self.base) else { throw JioSaavnError.badResponse }
        comps.queryItems = [
            URLQueryItem(name: "__call", value: "search.getResults"),
            URLQueryItem(name: "_format", value: "json"),
            URLQueryItem(name: "_marker", value: "0"),
            URLQueryItem(name: "api_version", value: "4"),
            URLQueryItem(name: "ctx", value: "android"),
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "n", value: "\(limit)")
        ]
        guard let url = comps.url else { throw JioSaavnError.badResponse }
        let (data, _) = try await transport(Self.request(url))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else {
            return []
        }
        return results.compactMap { item in
            guard let id = item["id"] as? String, let title = item["title"] as? String else { return nil }
            let more = item["more_info"] as? [String: Any] ?? [:]
            var artist = (item["artist"] as? String) ?? ""
            if let map = more["artistMap"] as? [String: Any],
               let primaries = map["primary_artists"] as? [[String: Any]] {
                let names = primaries.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
                if !names.isEmpty { artist = names.joined(separator: ", ") }
            }
            let seconds = Int(more["duration"] as? String ?? "") ?? (more["duration"] as? Int) ?? 0
            let image = Self.hires((item["image"] as? String) ?? "")
            var result = MusicCatalogTrack(
                id: MusicCatalogID(source: .jiosaavn, rawValue: id),
                title: title,
                artist: artist,
                durationSeconds: seconds,
                artworkURL: URL(string: image),
                permalinkURL: nil,
                isStreamable: true
            )
            result.albumTitle = more["album"] as? String
                ?? item["album"] as? String
            return result
        }
    }

    func resolveStreamURL(for rawId: String) async throws -> URL {
        guard var comps = URLComponents(string: Self.base) else { throw JioSaavnError.badResponse }
        comps.queryItems = [
            URLQueryItem(name: "__call", value: "song.getDetails"),
            URLQueryItem(name: "_format", value: "json"),
            URLQueryItem(name: "_marker", value: "0"),
            URLQueryItem(name: "api_version", value: "4"),
            URLQueryItem(name: "ctx", value: "android"),
            URLQueryItem(name: "pids", value: rawId)
        ]
        guard let url = comps.url else { throw JioSaavnError.badResponse }
        let (data, _) = try await transport(Self.request(url))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JioSaavnError.badResponse
        }
        let song: [String: Any]?
        if let songs = root["songs"] as? [[String: Any]] {
            song = songs.first
        } else {
            song = root[rawId] as? [String: Any] ?? root.values.first as? [String: Any]
        }
        guard let more = song?["more_info"] as? [String: Any],
              let encrypted = more["encrypted_media_url"] as? String,
              let decrypted = Self.decrypt(encrypted) else {
            throw JioSaavnError.noStream
        }
        let supports320 = (more["320kbps"] as? String)?.lowercased() == "true"
            || (more["320kbps"] as? Bool) == true
        guard let streamURL = Self.bestURL(decrypted, supports320: supports320) else {
            throw JioSaavnError.noStream
        }
        return streamURL
    }

    // MARK: - Helpers

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("49.36.0.1", forHTTPHeaderField: "X-Forwarded-For")
        return request
    }

    private static func hires(_ image: String) -> String {
        image
            .replacingOccurrences(of: "150x150", with: "500x500")
            .replacingOccurrences(of: "50x50", with: "500x500")
    }

    /// DES/ECB/PKCS5 with the fixed key the desktop catalogue uses.
    static func decrypt(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let key = Array("38346591".utf8)
        guard key.count == kCCKeySizeDES, data.count % kCCBlockSizeDES == 0 else { return nil }
        var output = Data(count: data.count + kCCBlockSizeDES)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outBuffer -> Int32 in
            data.withUnsafeBytes { inBuffer -> Int32 in
                key.withUnsafeBytes { keyBuffer -> Int32 in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmDES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBuffer.baseAddress, kCCKeySizeDES, nil,
                        inBuffer.baseAddress, data.count,
                        outBuffer.baseAddress, outBuffer.count,
                        &moved
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return String(data: output.prefix(moved), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func bestURL(_ decrypted: String, supports320: Bool) -> URL? {
        guard !decrypted.isEmpty else { return nil }
        var string = decrypted
        if supports320,
           let range = string.range(of: "_(48|96|160|320)\\.(mp4|aac|mp3)", options: .regularExpression) {
            let matched = String(string[range])
            let ext = (matched as NSString).pathExtension
            string.replaceSubrange(range, with: "_320.\(ext)")
        }
        return URL(string: string)
    }
}
