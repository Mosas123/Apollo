import SwiftUI

/// Uses the selected profile's artwork without guessing identity from its name.
struct ArtistAvatarImageView: View {
    let name: String
    let fallbackURL: String?
    var contentMode: ContentMode = .fill
    var artistID: String? = nil

    @State private var resolvedURL: String?
    @State private var resolvedIdentity: String?

    private var identityKey: String { "\(artistID ?? "")|\(name)|\(fallbackURL ?? "")" }

    var body: some View {
        AsyncImageView(url: (resolvedIdentity == identityKey ? resolvedURL : nil) ?? fallbackURL, contentMode: contentMode)
            .task(id: identityKey) {
                resolvedURL = nil
                resolvedIdentity = identityKey
                guard !name.isEmpty else { return }
                let youTubeURL = fallbackURL.flatMap { URL(string: $0) }
                guard let resolved = await ArtistImageResolver.avatarImageURL(
                    name: name,
                    youTubeURL: youTubeURL,
                    artistID: artistID
                ) else { return }
                guard !Task.isCancelled else { return }
                if resolved.absoluteString != fallbackURL {
                    resolvedURL = resolved.absoluteString
                }
            }
    }
}
