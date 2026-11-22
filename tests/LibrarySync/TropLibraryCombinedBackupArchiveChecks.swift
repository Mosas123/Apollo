import Foundation

@main
enum TropLibraryCombinedBackupArchiveChecks {
    static let date = Date(timeIntervalSince1970: 1_780_000_000)
    static let recordingID = "a0000000-0000-4000-8000-000000000001"
    static let playlistID = "a0000000-0000-4000-8000-000000000002"
    static let entryID = "a0000000-0000-4000-8000-000000000003"
    static let aliasID = "a0000000-0000-4000-8000-000000000004"

    static func example() -> TropLibraryCombinedBackupSnapshot {
        let legacy = TropLibraryBackupSnapshot(
            tracks: [
                .init(
                    id: "legacy-video-1", title: "Legacy Song", artistName: "Artist",
                    albumName: nil, duration: 180, liked: true, inLibrary: date,
                    isEpisode: false, createdAt: date
                )
            ],
            albums: [], artists: [],
            playlists: [
                .init(
                    id: "legacy-playlist-1", name: "Old Playlist",
                    browseId: nil, bookmarkedAt: date, isEditable: true
                )
            ],
            playlistEntries: [
                .init(playlistId: "legacy-playlist-1", songId: "legacy-video-1", position: 0)
            ],
            podcasts: [], episodes: []
        )
        let modern = TropLibraryV2RecoverySnapshot(
            items: [
                .init(
                    id: recordingID, kind: "recording", title: "V2 Song",
                    artistOrAuthor: "Artist", durationSeconds: 210,
                    savedAt: date, likedAt: date, createdAt: date, modifiedAt: date
                ),
                .init(
                    id: playlistID, kind: "playlist", title: "New Playlist",
                    artistOrAuthor: nil, durationSeconds: 0,
                    savedAt: date, likedAt: nil, createdAt: date, modifiedAt: date
                )
            ],
            aliases: [
                .init(
                    id: aliasID, itemID: recordingID, kind: "recording",
                    provider: "youtube", scope: "global", externalID: "public-video-2"
                )
            ],
            playlistEntries: [
                .init(
                    id: entryID, playlistID: playlistID, recordingID: recordingID,
                    position: 0, createdAt: date
                )
            ],
            radioFavorites: [], importLedger: [], legacyRelations: [],
            omittedPrivateAliases: 2
        )
        return .init(legacy: legacy, libraryV2: modern)
    }

    static func main() throws {
        let original = example()
        let bytes = try TropLibraryCombinedBackupArchive.encode(original, createdAt: date)
        let recovered = try TropLibraryCombinedBackupArchive.decode(bytes)
        precondition(recovered.format == TropLibraryCombinedBackupArchive.format)
        precondition(recovered.library == original)
        precondition(recovered.payloadSHA256.count == 64)

        let text = String(decoding: bytes, as: UTF8.self)
        precondition(!text.contains("addon:"))
        precondition(!text.contains("token"))
        precondition(!text.contains("local_path"))

        // A tampered payload is rejected even when syntactically valid JSON.
        let damaged = text.replacingOccurrences(of: "Legacy Song", with: "Wrong Song")
        precondition(damaged != text)
        do {
            _ = try TropLibraryCombinedBackupArchive.decode(Data(damaged.utf8))
            preconditionFailure("Expected invalid checksum")
        } catch TropLibraryCombinedBackupError.checksumMismatch {}

        // Reject future/unknown formats without attempting a restore.
        let future = text.replacingOccurrences(
            of: "\"format\":\"trop-library-combined-metadata\"",
            with: "\"format\":\"unknown-backup-format\""
        )
        precondition(future != text)
        do {
            _ = try TropLibraryCombinedBackupArchive.decode(Data(future.utf8))
            preconditionFailure("Expected unsupported version")
        } catch TropLibraryCombinedBackupError.unsupportedVersion {}

        // Never accept a credentials-bearing, unexportable add-on alias.
        let privateAlias = TropLibraryV2RecoverySnapshot.Alias(
            id: aliasID, itemID: recordingID, kind: "recording",
            provider: "addon", scope: "global",
            externalID: "addon:private-manifest-token"
        )
        let unsafe = TropLibraryCombinedBackupSnapshot(
            legacy: original.legacy,
            libraryV2: .init(
                items: original.libraryV2.items, aliases: [privateAlias],
                playlistEntries: original.libraryV2.playlistEntries,
                radioFavorites: [], importLedger: [], legacyRelations: [],
                omittedPrivateAliases: 0
            )
        )
        do {
            _ = try TropLibraryCombinedBackupArchive.encode(unsafe)
            preconditionFailure("Must reject private source material")
        } catch TropLibraryCombinedBackupError.invalidPayload {}

        // Both legacy and V2 data must survive serialization as distinct
        // collections; never silently deduplicate by a YouTube video ID.
        precondition(recovered.library.legacy.tracks.count == 1)
        precondition(recovered.library.libraryV2.items.count == 2)
        precondition(recovered.library.legacy.playlistEntries.count == 1)
        precondition(recovered.library.libraryV2.playlistEntries.count == 1)
        print("Combined legacy+V2 metadata archive, integrity and privacy checks passed")
    }
}
