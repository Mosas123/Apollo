import Foundation

/// Catalogue identity is separate from YouTube's `videoId`.
/// Persist these keys rather than relying on a provider's raw ID being globally unique.
enum MusicCatalogSource: String, Codable, Hashable, Sendable {
    case youtube
    case audius
    case jamendo
    case qobuz
    case pencari
    case jiosaavn
    case addon
    case podcast
}

struct MusicCatalogID: Codable, Hashable, Sendable {
    let source: MusicCatalogSource
    let rawValue: String

    var storageKey: String { "\(source.rawValue):\(rawValue)" }

    init(source: MusicCatalogSource, rawValue: String) {
        self.source = source
        self.rawValue = rawValue
    }

    /// Only provider-scoped IDs are parsed. Legacy YouTube IDs stay unchanged.
    init?(storageKey: String) {
        guard let separator = storageKey.firstIndex(of: ":"),
              let source = MusicCatalogSource(rawValue: String(storageKey[..<separator])),
              source != .youtube else { return nil }
        let rawValue = String(storageKey[storageKey.index(after: separator)...])
        guard !rawValue.isEmpty else { return nil }
        self.init(source: source, rawValue: rawValue)
    }
}

/// Provider-agnostic search result. This intentionally does not conform to `SongItem`:
/// `SongItem.videoId` and the existing queue currently assume YouTube IDs.
struct MusicCatalogTrack: Hashable, Sendable {
    let id: MusicCatalogID
    let title: String
    let artist: String
    let durationSeconds: Int
    let artworkURL: URL?
    let permalinkURL: URL?
    let isStreamable: Bool
    var isrc: String? = nil
}

enum MusicCatalogError: Error, Equatable {
    case invalidURL
    case httpStatus(Int)
    case wrongProvider
    case unavailableTrack
}

/// A catalogue provider must supply a playable URL only for tracks permitted
/// for unauthenticated full-length streaming. The player owns the actual request.
protocol MusicCatalogProvider: Sendable {
    var source: MusicCatalogSource { get }
    func searchTracks(query: String, limit: Int) async throws -> [MusicCatalogTrack]
    func streamURL(for track: MusicCatalogTrack) throws -> URL
}

/// Existing queues store raw YouTube video IDs; external providers use a
/// namespaced ID such as `audius:D7KyD`. Keep routing deterministic.
enum MusicPlaybackIdentity {
    static func isAudius(_ playbackID: String?) -> Bool {
        playbackID?.hasPrefix("audius:") == true
    }

    static func isQobuz(_ playbackID: String?) -> Bool {
        playbackID?.hasPrefix("qobuz:") == true
    }

    /// PencariMusic was removed from the app; ids still saved in queues and
    /// libraries are played through the installed add-ons instead.
    static func isLegacyPencari(_ playbackID: String?) -> Bool {
        playbackID?.hasPrefix("pencari:") == true
    }

    static func isJioSaavn(_ playbackID: String?) -> Bool {
        playbackID?.hasPrefix("jiosaavn:") == true
    }

    static func isAddon(_ playbackID: String?) -> Bool {
        playbackID?.hasPrefix("addon:") == true
    }

    static func isPodcast(_ playbackID: String?) -> Bool {
        playbackID?.hasPrefix("podcast:") == true
    }

    /// Human-readable origin of the current stream (not the YouTube transport
    /// client). Shown in the player menu.
    static func sourceLabel(_ playbackID: String?) -> String {
        if isQobuz(playbackID) { return "Qobuz" }
        if isLegacyPencari(playbackID) { return "PencariMusic (legacy)" }
        if isJioSaavn(playbackID) { return "JioSaavn" }
        if isAddon(playbackID) { return "Music Add-on" }
        if isPodcast(playbackID) { return "Podcast RSS" }
        if isAudius(playbackID) { return "Audius" }
        return "YouTube"
    }

    static func isExternal(_ playbackID: String?) -> Bool {
        isAudius(playbackID) || isQobuz(playbackID)
            || isJioSaavn(playbackID) || isAddon(playbackID)
            || isPodcast(playbackID)
    }

    static func isYouTube(_ playbackID: String?) -> Bool {
        guard let playbackID, !playbackID.isEmpty else { return false }
        // Radio, Audius, Jamendo and future sources are not YouTube IDs.
        return !playbackID.contains(":")
    }
}
