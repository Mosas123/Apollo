import Foundation

/// Saves the song currently playing on a radio stream: looks it up on YouTube
/// Music and downloads it into the library.
@MainActor
enum RadioLiveSaver {
    static func download(artist: String, title: String) async -> String {
        let query = [artist, title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return "No song detected." }

        do {
            let raw = try await SearchService.shared.search(query: query)
            let sections = SearchParser.parseSearchResults(from: raw)
            let song = sections
                .first(where: { $0.title == "Songs" })?
                .items
                .compactMap { item -> SongItem? in
                    if case .song(let song) = item { return song }
                    return nil
                }
                .first
            guard let song else { return "Song not found on YouTube Music." }
            await DownloadManager.shared.download(song: song)
            return "Saving “\(song.title)”…"
        } catch {
            return "Could not save: \(error.localizedDescription)"
        }
    }
}
