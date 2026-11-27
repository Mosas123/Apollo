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
        guard !query.isEmpty else { return String(localized: "No song detected.") }

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
            guard let song else { return String(localized: "Song not found on YouTube Music.") }
            await DownloadManager.shared.download(song: song)
            return String.localizedStringWithFormat(NSLocalizedString("Saving “%@”…", comment: "Radio song being saved"), song.title)
        } catch {
            return String.localizedStringWithFormat(NSLocalizedString("Could not save: %@", comment: "Radio download error"), error.localizedDescription)
        }
    }
}
