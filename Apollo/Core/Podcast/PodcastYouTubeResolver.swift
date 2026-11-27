import Foundation
@preconcurrency import ApolloTube

/// Podcast episodes are rarely indexed by YouTube Music. This resolver uses
/// normal YouTube web search and matches the show/channel, episode title and
/// duration before handing the video id to the audio pipeline.
@MainActor
final class PodcastYouTubeResolver {
    static let shared = PodcastYouTubeResolver()

    private struct Candidate {
        let videoId: String
        let title: String
        let channel: String
        let duration: Int
        let publishedText: String?
        let score: Int
    }

    private struct Entry {
        let song: SongItem?
        let at: Date
    }

    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 6 * 60 * 60

    func resolve(for song: SongItem) async -> SongItem? {
        guard song.contentKind == .episode || song.videoId.hasPrefix("spotify:episode:") else {
            return nil
        }
        let cacheKey = song.catalogID ?? song.videoId
        if let entry = cache[cacheKey], Date().timeIntervalSince(entry.at) < ttl {
            return entry.song
        }

        let show = song.artists.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let queries = [
            "\(show) \(song.title)",
            "\(song.title) \(show) podcast",
            "\(show) podcast \(song.title)"
        ].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var candidates: [Candidate] = []
        for query in queries {
            guard let json = try? await SearchService.shared.search(query: query, client: .web),
                  !Task.isCancelled else { continue }
            for video in Self.videoRenderers(in: json) {
                if let candidate = Self.candidate(from: video, show: show, song: song) {
                    candidates.append(candidate)
                }
            }
            if candidates.contains(where: { $0.score >= 120 }) { break }
        }

        guard let best = candidates.max(by: { $0.score < $1.score }), best.score >= 70 else {
            cache[cacheKey] = Entry(song: nil, at: Date())
            return nil
        }

        var resolved = song
        resolved.videoId = best.videoId
        resolved.catalogID = song.catalogID
        resolved.sourceAttribution = "Podcast audio · YouTube"
        cache[cacheKey] = Entry(song: resolved, at: Date())
        return resolved
    }

    private static func candidate(from video: [String: Any], show: String, song: SongItem) -> Candidate? {
        guard let videoId = video["videoId"] as? String, !videoId.isEmpty else { return nil }
        let title = text(video["title"]) ?? ""
        let channel = text(video["ownerText"])
            ?? text(video["longBylineText"])
            ?? text(video["shortBylineText"])
            ?? ""
        guard !title.isEmpty else { return nil }

        let duration = durationSeconds(text(video["lengthText"]))
        guard duration == 0 || duration >= 60 else { return nil }

        let wantedTitle = TextMatch.normalizeTitle(song.title)
        let candidateTitle = TextMatch.normalizeTitle(title)
        guard !wantedTitle.isEmpty else { return nil }
        guard candidateTitle == wantedTitle
            || candidateTitle.contains(wantedTitle)
            || wantedTitle.contains(candidateTitle) else { return nil }

        var score = 0
        if candidateTitle == wantedTitle { score += 50 } else { score += 25 }

        let wantedShow = TextMatch.normalizeArtist(show)
        let candidateChannel = TextMatch.normalizeArtist(channel)
        if !wantedShow.isEmpty, !candidateChannel.isEmpty {
            if candidateChannel == wantedShow { score += 60 }
            else if candidateChannel.contains(wantedShow) || wantedShow.contains(candidateChannel) { score += 35 }
        }

        if song.duration > 0, duration > 0 {
            let delta = abs(duration - song.duration)
            if delta <= 10 { score += 30 }
            else if delta <= 45 { score += 10 }
            else if delta > 180 { return nil }
        }

        let lower = title.lowercased()
        if lower.contains("shorts") || lower.contains("clip") || lower.contains("reaction") {
            score -= 40
        }

        return Candidate(
            videoId: videoId,
            title: title,
            channel: channel,
            duration: duration,
            publishedText: text(video["publishedTimeText"]),
            score: score
        )
    }

    private static func videoRenderers(in value: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []
        if let dict = value as? [String: Any] {
            if let video = dict["videoRenderer"] as? [String: Any] {
                result.append(video)
            }
            for child in dict.values {
                result.append(contentsOf: videoRenderers(in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.append(contentsOf: videoRenderers(in: child))
            }
        }
        return result
    }

    private static func text(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String, !simple.isEmpty { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func durationSeconds(_ value: String?) -> Int {
        guard let value, !value.isEmpty else { return 0 }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return 0 }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts[0]
    }
}
