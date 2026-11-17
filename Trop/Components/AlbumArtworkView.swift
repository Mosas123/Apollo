import SwiftUI

/// Shows the album cover (resolved once per album, cached) falling back to the
/// song's YouTube thumbnail. Used in list rows so every track of an album shows
/// the same cover without a request per row.
struct AlbumArtworkView: View {
    let album: String?
    let artist: String?
    let fallbackURL: String?

    @State private var resolvedURL: String?

    var body: some View {
        AsyncImageView(url: resolvedURL ?? fallbackURL)
            .task(id: taskKey) {
                guard resolvedURL == nil,
                      let album, !album.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                guard let resolved = await AlbumCoverStore.shared.coverURL(
                    album: album,
                    artist: artist ?? ""
                ) else { return }
                if resolved.absoluteString != fallbackURL {
                    resolvedURL = resolved.absoluteString
                }
            }
    }

    private var taskKey: String {
        "\(album ?? "")|\(artist ?? "")"
    }
}
