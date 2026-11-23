import SwiftUI

/// Album artwork is a *display enrichment*, never a source of audio, a
/// recording identity, or a portable backup field. The catalogue query works
/// without a YouTube login, and a missing match keeps the honest placeholder.
struct TropLibraryV2ArtworkView: View {
    let title: String
    let artist: String?
    let durationSeconds: Int

    @State private var resolvedURL: String?

    private var lookupKey: String {
        "\(title)|\(artist ?? "")|\(durationSeconds)"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
            if let resolvedURL {
                AsyncImageView(url: resolvedURL)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
        .task(id: lookupKey) {
            resolvedURL = nil
            guard let artist,
                  !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            let candidate = await MetadataResolver.enrich(
                title: title,
                artist: artist,
                duration: durationSeconds > 0 ? durationSeconds : nil
            )
            guard !Task.isCancelled,
                  let candidate,
                  let url = TropLibraryV2ArtworkSelectionPolicy.url(
                    title: title, artist: artist, metadata: candidate
                  )
            else { return }
            resolvedURL = url.absoluteString
        }
    }
}

/// The cover is only displayed when an independent catalogue confirms the
/// recording title and artist. Never guess using a YouTube ID or fetch media.
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
