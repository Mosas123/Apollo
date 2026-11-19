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
