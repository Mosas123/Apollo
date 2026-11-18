import Foundation

/// YouTube Music / LyricFind lyrics. Uses `next` to find the lyrics browse id
/// (MUSIC_PAGE_TYPE_TRACK_LYRICS) and `browse` with the mobile client, which
/// exposes timed lines (`cueRange`). Falls back to the plain description shelf.
struct YTMusicLyricsProvider: LyricsProvider {
    let id = "ytmusic"
    let name = "YouTube Music"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        guard let videoId = query.videoId, !videoId.isEmpty else {
            throw LyricsError.notFound
        }
        let next = try await InnerTubeClient.tropShared.next(videoId: videoId)
        guard let browseId = Self.lyricsBrowseId(next.value) else {
            throw LyricsError.notFound
        }
        let response = try await InnerTubeClient.tropShared.browse(
            browseId: browseId,
            client: .mobile
        )
        if let timed = Self.timedLines(response.value), !timed.isEmpty {
            return timed
        }
        if let plain = Self.plainLyrics(response.value), !plain.isEmpty {
            let lines = LyricsText.plainLines(plain)
            if !lines.isEmpty { return lines }
        }
        throw LyricsError.notFound
    }

    // MARK: - next

    static func lyricsBrowseId(_ root: [String: Any]) -> String? {
        guard let watchNext = value(
            at: ["contents", "singleColumnMusicWatchNextResultsRenderer", "tabbedRenderer",
                  "watchNextTabbedResultsRenderer"],
            in: root
        ) as? [String: Any],
              let tabs = watchNext["tabs"] as? [[String: Any]] else { return nil }
        for tab in tabs {
            guard let endpoint = value(at: ["tabRenderer", "endpoint", "browseEndpoint"], in: tab) as? [String: Any],
                  let pageType = value(
                    at: ["browseEndpointContextSupportedConfigs",
                          "browseEndpointContextMusicConfig", "pageType"],
                    in: endpoint
                  ) as? String,
                  pageType == "MUSIC_PAGE_TYPE_TRACK_LYRICS",
                  let browseId = endpoint["browseId"] as? String else { continue }
            return browseId
        }
        return nil
    }

    // MARK: - browse

    static func timedLines(_ root: [String: Any]) -> [LyricLine]? {
        guard let data = findValue(forKey: "timedLyricsData", in: root) as? [[String: Any]] else {
            return nil
        }
        let lines: [LyricLine] = data.compactMap { entry in
            guard let text = entry["lyricLine"] as? String,
                  let cue = entry["cueRange"] as? [String: Any],
                  let startMillis = cue["startTimeMilliseconds"] as? Double
                    ?? (cue["startTimeMilliseconds"] as? Int).map(Double.init) else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return LyricLine(text: trimmed, startTime: startMillis / 1000)
        }
        return lines.isEmpty ? nil : lines
    }

    static func plainLyrics(_ root: [String: Any]) -> String? {
        if let lyrics = findValue(forKey: "lyrics", in: root) as? String, !lyrics.isEmpty {
            return lyrics
        }
        if let runs = findValue(forKey: "runs", in: root) as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }.joined()
            if text.count > 20 { return text }
        }
        return nil
    }

    // MARK: - JSON walking

    private static func value(at path: [String], in root: Any) -> Any? {
        var current: Any? = root
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current
    }

    private static func findValue(forKey key: String, in node: Any) -> Any? {
        if let dict = node as? [String: Any] {
            if let hit = dict[key] { return hit }
            for value in dict.values {
                if let hit = findValue(forKey: key, in: value) { return hit }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let hit = findValue(forKey: key, in: value) { return hit }
            }
        }
        return nil
    }
}
