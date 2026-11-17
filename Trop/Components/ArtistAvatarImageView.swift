import SwiftUI

/// Circular artist avatar that swaps the YouTube thumbnail for the same artist
/// photo used by the hero (Deezer/Wikimedia), so small and large contexts show
/// one consistent image — like Apple Music.
struct ArtistAvatarImageView: View {
    let name: String
    let fallbackURL: String?
    var contentMode: ContentMode = .fill

    @State private var resolvedURL: String?

    var body: some View {
        AsyncImageView(url: resolvedURL ?? fallbackURL, contentMode: contentMode)
            .task(id: name) {
                guard resolvedURL == nil, !name.isEmpty else { return }
                let youTubeURL = fallbackURL.flatMap { URL(string: $0) }
                guard let resolved = await ArtistImageResolver.avatarImageURL(
                    name: name,
                    youTubeURL: youTubeURL
                ) else { return }
                if resolved.absoluteString != fallbackURL {
                    resolvedURL = resolved.absoluteString
                }
            }
    }
}
