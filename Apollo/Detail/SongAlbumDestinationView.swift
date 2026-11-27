import SwiftUI
@preconcurrency import SwiftyTube

/// Resolves missing album links on demand, without changing the song or queue.
struct SongAlbumDestinationView: View {
    let song: SongItem
    @State private var albumID: String?
    @State private var isLoading = true
    @State private var lookupFailed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let albumID {
                AlbumDetailView(browseId: albumID)
            } else if isLoading {
                ProgressView("Finding album…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label(LocalizedStringKey(lookupFailed ? "Couldn't load album" : "Album unavailable"), systemImage: "square.stack")
                } description: {
                    Text(LocalizedStringKey(lookupFailed
                         ? "Check your connection and try again."
                         : "No matching album was found for this song."))
                } actions: {
                    Button("Try Again") { attempt += 1 }
                }
            }
        }
        .task(id: attempt) {
            isLoading = true
            lookupFailed = false
            defer { isLoading = false }
            do {
                let resolved = try await SongAlbumResolver.albumID(for: song)
                guard !Task.isCancelled else { return }
                albumID = resolved
            } catch {
                guard !Task.isCancelled else { return }
                lookupFailed = true
            }
        }
    }
}

@MainActor
enum SongAlbumResolver {
    static func albumID(for song: SongItem) async throws -> String? {
        if let id = song.firstAlbumBrowseId, !id.isEmpty { return id }
        guard MusicPlaybackIdentity.isYouTube(song.videoId) else { return nil }
        let client = InnerTubeClient.apolloShared

        // Only inspect the requested video's own queue entry. Other entries in
        // next() are recommendations and can point at entirely different albums.
        if let json = try? await client.next(videoId: song.videoId).value,
           let id = albumID(in: json, videoID: song.videoId) { return id }
        try Task.checkCancellation()

        // Search results frequently omit album links. Find the canonical track
        // first, then require both release title and performer in our catalogue.
        guard let metadata = await MetadataResolver.enrich(
            title: song.title,
            artist: song.artistNamesDisplay,
            album: song.album,
            duration: song.duration
        ), let album = metadata.album, !album.isEmpty else { return nil }
        try Task.checkCancellation()
        // Use an independent request; SearchService cancels interactive typing.
        let json = try await client.search(query: "\(metadata.artist) \(album)").value
        try Task.checkCancellation()
        let matches = SearchParser.parseSearchResults(from: json).flatMap(\.items).compactMap { item -> String? in
            guard case .album(let candidate) = item,
                  TextMatch.normalizeTitle(candidate.title) == TextMatch.normalizeTitle(album),
                  candidate.artists.contains(where: { TextMatch.artistsMatch($0.name, metadata.artist) }) else { return nil }
            return candidate.browseId
        }
        let ids = Set(matches)
        return ids.count == 1 ? ids.first : nil
    }

    static func albumID(in node: Any, videoID: String) -> String? {
        if let dictionary = node as? [String: Any] {
            if let renderer = dictionary["playlistPanelVideoRenderer"] as? [String: Any],
               renderer["videoId"] as? String == videoID {
                return albumEndpoint(in: renderer)
            }
            for key in dictionary.keys.sorted() {
                if let child = dictionary[key], let id = albumID(in: child, videoID: videoID) { return id }
            }
        } else if let array = node as? [Any] {
            for child in array {
                if let id = albumID(in: child, videoID: videoID) { return id }
            }
        }
        return nil
    }

    private static func albumEndpoint(in node: Any) -> String? {
        if let dictionary = node as? [String: Any] {
            if let endpoint = dictionary["browseEndpoint"] as? [String: Any],
               let id = endpoint["browseId"] as? String {
                let configs = endpoint["browseEndpointContextSupportedConfigs"] as? [String: Any]
                let music = configs?["browseEndpointContextMusicConfig"] as? [String: Any]
                if id.hasPrefix("MPREb_") || music?["pageType"] as? String == "MUSIC_PAGE_TYPE_ALBUM" {
                    return id
                }
            }
            for key in dictionary.keys.sorted() {
                if let child = dictionary[key], let id = albumEndpoint(in: child) { return id }
            }
        } else if let array = node as? [Any] {
            for child in array {
                if let id = albumEndpoint(in: child) { return id }
            }
        }
        return nil
    }
}
