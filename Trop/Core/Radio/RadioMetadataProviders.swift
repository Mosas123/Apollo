import Foundation

struct RadioNowPlaying: Equatable, Sendable {
    let artist: String
    let title: String
    let album: String?
    let coverURL: URL?
}

protocol RadioMetadataProvider: Sendable {
    func metadata(for streamURL: URL, stationName: String) async -> RadioNowPlaying?
}

/// Per-broadcaster now-playing APIs for stations that do not expose ICY.
/// Radio Paradise is the first one; add others here as they are validated.
enum RadioMetadataProviders {
    static func provider(for streamURL: URL, stationName: String) -> (any RadioMetadataProvider)? {
        if RadioParadiseProvider.matches(streamURL: streamURL, stationName: stationName) {
            return RadioParadiseProvider()
        }
        if TritonProvider.matches(streamURL: streamURL) {
            return TritonProvider()
        }
        return nil
    }
}

/// Radio Paradise publishes JSON per channel. Their AAC/MP3 streams carry no
/// ICY; the FLAC+meta ones do, and this API also supplies the cover/album.
struct RadioParadiseProvider: RadioMetadataProvider {
    static func matches(streamURL: URL, stationName: String) -> Bool {
        let host = (streamURL.host ?? "").lowercased()
        let name = stationName.lowercased()
        return host.contains("radioparadise.com") || name.contains("radio paradise")
    }

    func metadata(for streamURL: URL, stationName: String) async -> RadioNowPlaying? {
        var components = URLComponents(string: "https://api.radioparadise.com/api/now_playing")
        components?.queryItems = [
            URLQueryItem(name: "chan", value: "\(Self.channel(streamURL: streamURL, stationName: stationName))"),
            URLQueryItem(name: "info", value: "true")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        let artist = payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard title.count >= 2, title.lowercased() != "null" else { return nil }
        let album = payload.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RadioNowPlaying(
            artist: artist,
            title: title,
            album: (album?.isEmpty == false) ? album : nil,
            coverURL: payload.cover.flatMap(URL.init(string:))
        )
    }

    /// Channel mapping from the stream filename or the Radio Browser name.
    private static func channel(streamURL: URL, stationName: String) -> Int {
        let haystack = (streamURL.absoluteString + " " + stationName).lowercased()
        if haystack.contains("2050") { return 5 }
        if haystack.contains("mellow") { return 1 }
        if haystack.contains("rock") { return 2 }
        if haystack.contains("global") { return 3 }
        if haystack.contains("beyond") { return 4 }
        return 0
    }

    private struct Payload: Decodable {
        let artist: String?
        let title: String?
        let album: String?
        let cover: String?
    }
}


/// StreamTheWorld (Triton) mounts publish JSON/XML now-playing. The public
/// stream usually redirects to a `*_SC` mount whose ICY blocks are empty, but
/// Triton answers for the base mount (e.g. CARACOL_RADIOAAC).
struct TritonProvider: RadioMetadataProvider {
    static func matches(streamURL: URL) -> Bool {
        let host = (streamURL.host ?? "").lowercased()
        return host.contains("streamtheworld.com")
    }

    func metadata(for streamURL: URL, stationName: String) async -> RadioNowPlaying? {
        for mount in Self.mounts(for: streamURL) {
            var components = URLComponents(string: "https://np.tritondigital.com/public/nowplaying")
            components?.queryItems = [
                URLQueryItem(name: "mountName", value: mount),
                URLQueryItem(name: "numberToFetch", value: "1"),
                URLQueryItem(name: "eventType", value: "track")
            ]
            guard let url = components?.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let xml = String(data: data, encoding: .utf8) else { continue }
            let fields = Self.properties(from: xml)
            let title = fields["cue_title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard title.count >= 2, title.caseInsensitiveCompare(stationName) != .orderedSame else { continue }
            let artist = (fields["track_artist_name"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let album = (fields["track_album_name"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return RadioNowPlaying(
                artist: artist,
                title: title,
                album: album.isEmpty ? nil : album,
                coverURL: fields["track_cover_url"].flatMap(URL.init(string:))
            )
        }
        return nil
    }

    /// Public stream URLs point at `.../MOUNT_SC` or `.../MOUNT.aac`; Triton
    /// needs the base mount.
    static func mounts(for streamURL: URL) -> [String] {
        var name = (streamURL.lastPathComponent.removingPercentEncoding ?? streamURL.lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for ext in [".aac", ".mp3", ".m3u8", ".m3u", ".pls"] where name.lowercased().hasSuffix(ext) {
            name = String(name.dropLast(ext.count))
        }
        var candidates: [String] = [name]
        if name.hasSuffix("_SC") { candidates.append(String(name.dropLast(3))) }
        for candidate in candidates {
            if candidate.hasSuffix("AAC") { candidates.append(String(candidate.dropLast(3))) }
            if candidate.hasSuffix("MP3") { candidates.append(String(candidate.dropLast(3))) }
        }
        var seen = Set<String>()
        return candidates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func properties(from xml: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<property name="([^"]+)"><!\[CDATA\[(.*?)\]\]></property>"#,
            options: [.dotMatchesLineSeparators]
        ) else { return [:] }
        let string = xml as NSString
        var result: [String: String] = [:]
        for match in regex.matches(in: xml, range: NSRange(location: 0, length: string.length)) {
            guard match.numberOfRanges == 3 else { continue }
            result[string.substring(with: match.range(at: 1))] =
                string.substring(with: match.range(at: 2))
        }
        return result
    }
}
