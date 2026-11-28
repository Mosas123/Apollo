import Foundation
import GRDB

struct PlaylistImportSummary: Sendable, Equatable {
    let playlistID: String
    let playlistName: String
    let imported: Int
    let skipped: Int
}

enum PlaylistImportError: Error, LocalizedError {
    case unreadableFile
    case noMatches

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "The selected file could not be read."
        case .noMatches: return "No songs from the file could be matched in the catalogue."
        }
    }
}

/// Imports a CSV exported by Exportify/Soundiiz into a local Apollo playlist.
/// It never downloads audio and never trusts a CSV URL as a stream source.
struct PlaylistImportService: Sendable {
    private static let maximumNetworkLookups = 80

    func importFile(at url: URL) async throws -> PlaylistImportSummary {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw PlaylistImportError.unreadableFile
        }
        let file = try PlaylistCSVImporter().parse(
            data: data,
            fileName: url.lastPathComponent
        )

        var songs: [SongItem] = []
        var seen = Set<String>()
        var skipped = 0
        var lookups = 0

        for row in file.rows {
            let song: SongItem?
            if let id = row.spotifyTrackID {
                song = Self.song(from: row, spotifyID: id)
            } else if lookups < Self.maximumNetworkLookups {
                lookups += 1
                song = await Self.lookup(row)
            } else {
                song = nil
            }

            guard let song else {
                skipped += 1
                continue
            }
            guard seen.insert(song.videoId).inserted else {
                skipped += 1
                continue
            }
            songs.append(song)
        }

        guard !songs.isEmpty else { throw PlaylistImportError.noMatches }

        let playlistID = UUID().uuidString
        let playlist = PlaylistEntity(
            id: playlistID,
            browseId: nil,
            name: file.name,
            thumbnailUrl: songs.first?.thumbnailUrl,
            isEditable: true,
            bookmarkedAt: Date(),
            remoteSongCount: songs.count
        )

        do {
            try await DatabaseService.shared.write { db in
                try playlist.save(db)
                for (position, song) in songs.enumerated() {
                    let existing = try SongEntity.fetchOne(db, key: song.videoId)
                    let entity = SongEntity.merging(
                        existing: existing,
                        id: song.videoId,
                        title: song.title,
                        artistName: song.artists.map(\.name).joined(separator: ", "),
                        albumName: song.album,
                        duration: song.duration,
                        thumbnailUrl: song.thumbnailUrl,
                        isEpisode: false
                    )
                    try entity.save(db)
                    try PlaylistSongMap(
                        id: nil,
                        playlistId: playlistID,
                        songId: song.videoId,
                        position: position,
                        setVideoId: nil
                    ).insert(db)
                }
            }
        } catch {
            Log.sync.error("Playlist CSV import failed: \(error)")
            throw error
        }

        return PlaylistImportSummary(
            playlistID: playlistID,
            playlistName: file.name,
            imported: songs.count,
            skipped: skipped
        )
    }

    private static func song(from row: PlaylistCSVRow, spotifyID: String) -> SongItem {
        let catalogID = SpotifyCatalogID.track(spotifyID)
        return SongItem(
            videoId: catalogID,
            title: row.title,
            artists: row.artist.isEmpty ? [] : [YTArtist(name: row.artist, id: nil)],
            album: row.album,
            albumId: nil,
            duration: max(0, row.durationSeconds),
            thumbnailUrl: row.thumbnailURL,
            isExplicit: row.isExplicit,
            playlistId: nil,
            likeStatus: nil,
            viewCount: nil,
            year: nil,
            isVideo: false,
            musicVideoType: nil,
            recordingPreference: .albumAudio,
            contentKind: .music,
            catalogID: catalogID,
            isrc: row.isrc,
            stationReason: nil,
            sourceAttribution: nil
        )
    }

    private static func lookup(_ row: PlaylistCSVRow) async -> SongItem? {
        let query = [row.title, row.artist].filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty,
              let results = try? await SpotifyCatalogProvider().search(query, limit: 8) else {
            return nil
        }
        let wantedTitle = TextMatch.normalizeTitle(row.title)
        let wantedArtist = TextMatch.normalizeArtist(row.artist)
        let match = results.tracks.first { track in
            TextMatch.normalizeTitle(track.title) == wantedTitle
                && (wantedArtist.isEmpty
                    || track.artists.contains { TextMatch.normalizeArtist($0.name) == wantedArtist })
                && MusicVersionPolicy.isCompatible(
                    candidateTitle: track.title,
                    requestedExplicit: row.isExplicit
                )
        }
        return match.map(SpotifyCatalogMapper.song(from:))
    }
}
