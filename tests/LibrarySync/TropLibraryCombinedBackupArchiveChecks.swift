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
        return .init(
            legacy: legacy, libraryV2: modern,
            legacyMemberships: [
                .init(
                    sourceRowID: 11, playlistID: "legacy-playlist-1",
                    songID: "legacy-video-1", position: 0
                )
            ],
            originScope: "a0000000-0000-4000-8000-000000000099", foreignTombstones: []
        )
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
            ),
            legacyMemberships: original.legacyMemberships,
            originScope: original.originScope, foreignTombstones: original.foreignTombstones
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
        precondition(recovered.library.legacyMemberships[0].sourceRowID == 11)

        // Reject duplicate legacy origin row IDs even if song metadata agrees.
        let duplicated = TropLibraryCombinedBackupSnapshot(
            legacy: original.legacy, libraryV2: original.libraryV2,
            legacyMemberships: [original.legacyMemberships[0], original.legacyMemberships[0]],
            originScope: original.originScope, foreignTombstones: original.foreignTombstones
        )
        do {
            _ = try TropLibraryCombinedBackupArchive.encode(duplicated)
            preconditionFailure("Duplicated origin membership must be rejected")
        } catch TropLibraryCombinedBackupError.invalidPayload {}

        // A correct ID attached to the wrong song or playlist is corruption.
        let mismatched = TropLibraryCombinedBackupSnapshot(
            legacy: original.legacy, libraryV2: original.libraryV2,
            legacyMemberships: [
                .init(
                    sourceRowID: 11, playlistID: "legacy-playlist-1",
                    songID: "different-song", position: 0
                )
            ],
            originScope: original.originScope, foreignTombstones: original.foreignTombstones
        )
        do {
            _ = try TropLibraryCombinedBackupArchive.encode(mismatched)
            preconditionFailure("Mismatched source identity must be rejected")
        } catch TropLibraryCombinedBackupError.invalidPayload {}

        // Missing the original membership mapping must never be silently
        // inferred from playlist position.
        let missing = TropLibraryCombinedBackupSnapshot(
            legacy: original.legacy, libraryV2: original.libraryV2,
            legacyMemberships: [],
            originScope: original.originScope, foreignTombstones: original.foreignTombstones
        )
        do {
            _ = try TropLibraryCombinedBackupArchive.encode(missing)
            preconditionFailure("Missing membership map must be rejected")
        } catch TropLibraryCombinedBackupError.invalidPayload {}
        // The future restore must map source membership IDs to the new
        // integer IDs allocated by SQLite, never reuse source row IDs.
        let ledgerSource = TropLibraryCombinedBackupSnapshot(
            legacy: original.legacy,
            libraryV2: .init(
                items: original.libraryV2.items,
                aliases: original.libraryV2.aliases,
                playlistEntries: original.libraryV2.playlistEntries,
                radioFavorites: original.libraryV2.radioFavorites,
                importLedger: [
                    .init(legacyMembershipID: 11, entryID: entryID, importedAt: date)
                ],
                legacyRelations: original.libraryV2.legacyRelations,
                omittedPrivateAliases: original.libraryV2.omittedPrivateAliases
            ),
            legacyMemberships: original.legacyMemberships,
            originScope: original.originScope, foreignTombstones: original.foreignTombstones
        )
        let remapArchive = try TropLibraryCombinedBackupArchive.encode(ledgerSource)
        let good = TropLibraryCombinedRestorePlanner.DestinationMembership(
            sourceRowID: 11, assignedRowID: 902,
            playlistID: "legacy-playlist-1", songID: "legacy-video-1",
            position: 0
        )
        let plan = try TropLibraryCombinedRestorePlanner.prepare(
            archive: remapArchive, insertedMemberships: [good]
        )
        precondition(plan.sourceToDestinationID == [11: 902])
        precondition(plan.remappedImportLedger.count == 1)
        precondition(plan.remappedImportLedger[0].legacyMembershipID == 902)
        precondition(plan.remappedImportLedger[0].entryID == entryID)

        // An empty/missing insertion list must never become a partial restore.
        do {
            _ = try TropLibraryCombinedRestorePlanner.prepare(
                archive: remapArchive, insertedMemberships: []
            )
            preconditionFailure("Must reject incomplete destination map")
        } catch TropLibraryCombinedRestorePlanner.Blocker.incompleteMembershipMapping {}

        // Matching position alone is not evidence of matching identity.
        let wrong = TropLibraryCombinedRestorePlanner.DestinationMembership(
            sourceRowID: 11, assignedRowID: 903,
            playlistID: "wrong-playlist", songID: "legacy-video-1",
            position: 0
        )
        do {
            _ = try TropLibraryCombinedRestorePlanner.prepare(
                archive: remapArchive, insertedMemberships: [wrong]
            )
            preconditionFailure("Must reject incorrect playlist identity")
        } catch TropLibraryCombinedRestorePlanner.Blocker.wrongMembershipIdentity {}

        let missingSource = TropLibraryCombinedRestorePlanner.DestinationMembership(
            sourceRowID: 99, assignedRowID: 904,
            playlistID: "legacy-playlist-1", songID: "legacy-video-1",
            position: 0
        )
        do {
            _ = try TropLibraryCombinedRestorePlanner.prepare(
                archive: remapArchive, insertedMemberships: [missingSource]
            )
            preconditionFailure("Must reject foreign source membership ID")
        } catch TropLibraryCombinedRestorePlanner.Blocker.unknownSourceMembership {}

        // A deleted source membership may still appear in the import ledger
        // (a tombstone). Never remap that ID to an unrelated live row.
        let tombstoneSource = TropLibraryCombinedBackupSnapshot(
            legacy: original.legacy,
            libraryV2: .init(
                items: original.libraryV2.items,
                aliases: original.libraryV2.aliases,
                playlistEntries: original.libraryV2.playlistEntries,
                radioFavorites: original.libraryV2.radioFavorites,
                importLedger: [
                    .init(legacyMembershipID: 99, entryID: nil, importedAt: date)
                ],
                legacyRelations: original.libraryV2.legacyRelations,
                omittedPrivateAliases: original.libraryV2.omittedPrivateAliases
            ),
            legacyMemberships: original.legacyMemberships,
            originScope: original.originScope, foreignTombstones: original.foreignTombstones
        )
        let orphanArchive = try TropLibraryCombinedBackupArchive.encode(tombstoneSource)
        let quarantine = try TropLibraryCombinedRestorePlanner.prepare(
            archive: orphanArchive, insertedMemberships: [good]
        )
        precondition(quarantine.foreignTombstones.count == 1)
        precondition(quarantine.foreignTombstones[0].originScope == original.originScope)
        precondition(quarantine.foreignTombstones[0].sourceMembershipID == 99)
        precondition(quarantine.remappedImportLedger.isEmpty)

        // A corrupt envelope is never accepted by the remap planner.
        do {
            _ = try TropLibraryCombinedRestorePlanner.prepare(
                archive: Data(damaged.utf8), insertedMemberships: [good]
            )
            preconditionFailure("Must reject tampered archive")
        } catch TropLibraryCombinedBackupError.checksumMismatch {}

        // Multiple source rows must map injectively to destination row IDs.
        let legacy2 = TropLibraryBackupSnapshot(
            tracks: original.legacy.tracks + [
                .init(
                    id: "legacy-video-2", title: "Second song", artistName: "Artist",
                    albumName: nil, duration: 181, liked: true, inLibrary: date,
                    isEpisode: false, createdAt: date
                )
            ], albums: original.legacy.albums,
            artists: original.legacy.artists, playlists: original.legacy.playlists,
            playlistEntries: original.legacy.playlistEntries + [
                .init(
                    playlistId: "legacy-playlist-1", songId: "legacy-video-2",
                    position: 1
                )
            ],
            podcasts: original.legacy.podcasts, episodes: original.legacy.episodes
        )
        let twoSource = TropLibraryCombinedBackupSnapshot(
            legacy: legacy2, libraryV2: original.libraryV2,
            legacyMemberships: original.legacyMemberships + [
                .init(
                    sourceRowID: 12, playlistID: "legacy-playlist-1",
                    songID: "legacy-video-2", position: 1
                )
            ],
            originScope: original.originScope, foreignTombstones: original.foreignTombstones
        )
        let twoArchive = try TropLibraryCombinedBackupArchive.encode(twoSource)
        let colliding = TropLibraryCombinedRestorePlanner.DestinationMembership(
            sourceRowID: 12, assignedRowID: 902,
            playlistID: "legacy-playlist-1", songID: "legacy-video-2",
            position: 1
        )
        do {
            _ = try TropLibraryCombinedRestorePlanner.prepare(
                archive: twoArchive, insertedMemberships: [good, colliding]
            )
            preconditionFailure("Must reject duplicate destination row IDs")
        } catch TropLibraryCombinedRestorePlanner.Blocker.duplicateDestinationID {}

        let foreign = TropLibraryCombinedBackupSnapshot.ForeignTombstone(
            originScope: original.originScope,
            sourceMembershipID: 99, entryID: nil, importedAt: date
        )
        let duplicate = TropLibraryCombinedBackupSnapshot(
            legacy: original.legacy, libraryV2: original.libraryV2,
            legacyMemberships: original.legacyMemberships,
            originScope: original.originScope, foreignTombstones: [foreign, foreign]
        )
        do {
            _ = try TropLibraryCombinedBackupArchive.encode(duplicate)
            preconditionFailure("Duplicated scoped tombstones must fail")
        } catch TropLibraryCombinedBackupError.invalidPayload {}
        // Historical entry references remain exportable after the V2 entry
        // is deleted; they are not live foreign-key references.
        let stale = TropLibraryCombinedBackupSnapshot.ForeignTombstone(
            originScope: original.originScope, sourceMembershipID: 100,
            entryID: "b0000000-0000-4000-8000-000000000001", importedAt: date
        )
        let history = TropLibraryCombinedBackupSnapshot(
            legacy: original.legacy, libraryV2: original.libraryV2,
            legacyMemberships: original.legacyMemberships,
            originScope: original.originScope, foreignTombstones: [stale]
        )
        let decodedHistory = try TropLibraryCombinedBackupArchive.decode(
            TropLibraryCombinedBackupArchive.encode(history)
        )
        precondition(decodedHistory.library.foreignTombstones == [stale])
        let badHistory = TropLibraryCombinedBackupSnapshot(
            legacy: original.legacy, libraryV2: original.libraryV2,
            legacyMemberships: original.legacyMemberships,
            originScope: original.originScope,
            foreignTombstones: [
                .init(
                    originScope: original.originScope, sourceMembershipID: 100,
                    entryID: "invalid-entry-id", importedAt: date
                )
            ]
        )
        do {
            _ = try TropLibraryCombinedBackupArchive.encode(badHistory)
            preconditionFailure("Invalid historical entry ID must fail")
        } catch TropLibraryCombinedBackupError.invalidPayload {}
        print("Combined legacy+V2 archive, scoped tombstones and remap checks passed")
    }
}
