import SwiftUI
@preconcurrency import SwiftyTube

/// Keeps artist lookup in the player's own navigation sheet when a song has
/// performer names but no browse IDs (common for stored and video results).
struct SongArtistDestinationView: View {
    let song: SongItem
    let artistName: String

    @State private var matches: [ArtistItem] = []
    @State private var isLoading = true
    @State private var lookupFailed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Finding artist…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matches.count == 1, let artist = matches.first {
                ArtistDetailView(browseId: artist.browseId)
            } else if !matches.isEmpty {
                // Homonyms must not silently send the user to the first hit.
                List(matches, id: \.browseId) { artist in
                    NavigationLink {
                        ArtistDetailView(browseId: artist.browseId)
                    } label: {
                        HStack(spacing: 12) {
                            ArtistAvatarImageView(
                                name: artist.name, fallbackURL: artist.thumbnailUrl,
                                artistID: artist.browseId
                            )
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            Text(artist.name)
                        }
                    }
                }
                .navigationTitle("Choose Artist")
            } else {
                ContentUnavailableView {
                    Label(lookupFailed ? "Couldn't load artist" : "Artist unavailable", systemImage: "music.mic")
                } description: {
                    Text(lookupFailed
                         ? "Check your connection and try again."
                         : "No matching artist was found for this song.")
                } actions: {
                    Button("Try Again") { attempt += 1 }
                }
            }
        }
        .task(id: "\(song.videoId)|\(artistName)|\(attempt)") {
            isLoading = true
            lookupFailed = false
            matches = []
            defer { isLoading = false }
            let wanted = TextMatch.normalizeArtist(artistName)
            guard !wanted.isEmpty else { return }
            do {
                // An independent request must not cancel Search's live query.
                let json = try await InnerTubeClient.tropShared.search(query: wanted).value
                guard !Task.isCancelled else { return }
                var seen = Set<String>()
                matches = SearchParser.parseSearchResults(from: json).flatMap(\.items).compactMap { item in
                    guard case .artist(let artist) = item,
                          TextMatch.normalizeArtist(artist.name) == wanted,
                          !artist.browseId.isEmpty,
                          seen.insert(artist.browseId).inserted else { return nil }
                    return artist
                }
            } catch {
                guard !Task.isCancelled else { return }
                lookupFailed = true
            }
        }
    }
}
