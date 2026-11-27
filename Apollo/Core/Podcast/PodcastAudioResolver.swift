import Foundation

struct PodcastAudioMatch: Sendable {
    let audioURL: URL
    let feedTitle: String
    let feedAuthor: String?
    let feedURL: URL
    let episodeTitle: String
    let mimeType: String?
}

/// Resolves a Spotify podcast episode to the publisher's public RSS enclosure.
/// Spotify never provides the audio; the RSS does.
actor PodcastAudioResolver {
    static let shared = PodcastAudioResolver()

    private struct Entry {
        let match: PodcastAudioMatch?
        let at: Date
    }

    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 6 * 60 * 60

    func resolve(for song: SongItem) async -> PodcastAudioMatch? {
        guard song.contentKind == .episode || song.videoId.hasPrefix("spotify:episode:") else {
            return nil
        }
        let key = song.catalogID ?? song.videoId
        if let entry = cache[key], Date().timeIntervalSince(entry.at) < ttl {
            return entry.match
        }

        let showName = song.artists.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !showName.isEmpty,
              let feed = await ITunesPodcastDirectory.shared.feed(for: showName),
              let feedURL = feed.feedURL,
              let content = await PodcastRSSFeedLoader.shared.content(for: feedURL) else {
            cache[key] = Entry(match: nil, at: Date())
            return nil
        }

        guard let episode = bestEpisode(for: song, in: content.episodes) else {
            cache[key] = Entry(match: nil, at: Date())
            return nil
        }

        let match = PodcastAudioMatch(
            audioURL: episode.audioURL,
            feedTitle: content.title,
            feedAuthor: content.author ?? feed.author,
            feedURL: feedURL,
            episodeTitle: episode.title,
            mimeType: episode.mimeType ?? mimeType(for: episode.audioURL)
        )
        cache[key] = Entry(match: match, at: Date())
        return match
    }

    private func bestEpisode(for song: SongItem, in episodes: [PodcastEpisode]) -> PodcastEpisode? {
        let wantedTitle = TextMatch.normalizeTitle(song.title)
        guard !wantedTitle.isEmpty else { return nil }

        let scored = episodes.compactMap { episode -> (PodcastEpisode, Int)? in
            let title = TextMatch.normalizeTitle(episode.title)
            var score = 0
            if title == wantedTitle {
                score += 100
            } else if !title.isEmpty, title.contains(wantedTitle) || wantedTitle.contains(title) {
                score += 50
            } else {
                return nil
            }

            if song.duration > 0, let duration = episode.duration, duration > 0 {
                let delta = abs(duration - song.duration)
                if delta <= 10 { score += 30 }
                else if delta <= 45 { score += 10 }
                else if delta > 180 { return nil }
            }
            return (episode, score)
        }

        return scored.max { $0.1 < $1.1 }?.0
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "aac": return "audio/aac"
        case "ogg", "opus": return "audio/ogg"
        default: return "audio/mpeg"
        }
    }
}
