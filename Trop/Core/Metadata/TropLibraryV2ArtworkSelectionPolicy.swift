import Foundation

/// Only display artwork from a known independent music catalogue, after
/// checking the returned title and performer. This is metadata, not audio.
enum TropLibraryV2ArtworkSelectionPolicy {
    static func url(
        title: String,
        artist: String,
        metadata: ResolvedMetadata
    ) -> URL? {
        guard ["iTunes", "Deezer", "MusicBrainz"].contains(metadata.source),
              TextMatch.recordingsMatch(metadata.title, title),
              TextMatch.artistsMatch(metadata.artist, artist),
              let url = metadata.artworkURL,
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return url
    }
}
