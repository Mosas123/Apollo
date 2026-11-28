import SwiftUI

/// Drop-in replacement for `AsyncImageView` on music surfaces. It paints the
/// current cover immediately and swaps in a catalogue-sized one when known.
struct SmartArtwork: View {
    let url: String?
    let subject: ArtworkSubject?
    var contentMode: ContentMode = .fill
    var onImageLoaded: ((UIImage) -> Void)? = nil

    @State private var upgradedURL: String?
    @State private var taskKey: String?

    private var identity: String { "\(url ?? "")|\(subject?.cacheKey ?? "")" }

    var body: some View {
        AsyncImageView(
            url: taskKey == identity ? (upgradedURL ?? url) : url,
            contentMode: contentMode,
            onImageLoaded: onImageLoaded
        )
        .task(id: identity) {
            taskKey = identity
            upgradedURL = nil
            guard let subject else { return }
            let resolved = await ArtworkResolver.upgrade(subject)
            guard !Task.isCancelled, taskKey == identity else { return }
            upgradedURL = resolved?.absoluteString
        }
    }
}

extension YTItem {
    var artworkSubject: ArtworkSubject? {
        switch self {
        case .song(let song):
            return .track(
                title: song.title,
                artist: song.artists.map(\.name).joined(separator: ", "),
                album: song.album,
                duration: song.duration
            )
        case .album(let album):
            return .album(
                title: album.title,
                artist: album.artists.map(\.name).joined(separator: ", ")
            )
        case .artist, .podcast, .episode, .playlist:
            // Identity cannot be verified from a name alone. Keep the
            // catalogue's own image instead of risking a namesake/wrong show.
            return nil
        }
    }
}
