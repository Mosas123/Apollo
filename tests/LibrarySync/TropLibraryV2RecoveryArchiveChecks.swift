import Foundation

@main
enum TropLibraryV2RecoveryArchiveChecks {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recording = "a0000000-0000-4000-8000-000000000001"
        let playlist = "a0000000-0000-4000-8000-000000000002"
        let episode = "a0000000-0000-4000-8000-000000000003"
        let entry = "a0000000-0000-4000-8000-000000000004"
        let radio = "a0000000-0000-4000-8000-000000000005"
        let alias = "a0000000-0000-4000-8000-000000000006"
        let relation = "a0000000-0000-4000-8000-000000000007"

        func sample(
            entries: [TropLibraryV2RecoverySnapshot.PlaylistEntry],
            sourceAliases: [TropLibraryV2RecoverySnapshot.Alias]
        ) -> TropLibraryV2RecoverySnapshot {
            TropLibraryV2RecoverySnapshot(
                items: [
                    .init(
                        id: recording, kind: "recording", title: "Una Canción",
                        artistOrAuthor: nil, durationSeconds: 180,
                        savedAt: now, likedAt: now, createdAt: now, modifiedAt: now
                    ),
                    .init(
                        id: playlist, kind: "playlist", title: "My Mix",
                        artistOrAuthor: nil, durationSeconds: 0, savedAt: now,
                        likedAt: nil, createdAt: now, modifiedAt: now
                    ),
                    .init(
                        id: episode, kind: "episode", title: "Episode",
                        artistOrAuthor: "Host", durationSeconds: 600,
                        savedAt: now, likedAt: nil, createdAt: now, modifiedAt: now
                    )
                ],
                aliases: sourceAliases,
                playlistEntries: entries,
                radioFavorites: [
                    .init(
                        id: radio,
                        stationUUID: "9617ba77-0601-11e8-ae97-52543be04c81",
                        name: "Latina Salsa", subtitle: "", addedAt: now
                    )
                ],
                importLedger: [
                    .init(legacyMembershipID: 3, entryID: entry, importedAt: now),
                    .init(legacyMembershipID: 4, entryID: nil, importedAt: now)
                ],
                legacyRelations: [
                    .init(
                        id: relation, ownerItemID: episode,
                        linkKind: "episode_podcast", externalID: "YT-podcast",
                        createdAt: now
                    )
                ],
                omittedPrivateAliases: 2
            )
        }

        let source = sample(
            entries: [
                .init(
                    id: entry, playlistID: playlist, recordingID: recording,
                    position: 0, createdAt: now
                )
            ],
            sourceAliases: [
                .init(
                    id: alias, itemID: recording, kind: "recording",
                    provider: "youtube", scope: "global", externalID: "abc123"
                )
            ]
        )
        let bytes = try TropLibraryV2RecoveryArchive.encode(source)
        let recovered = try TropLibraryV2RecoveryArchive.decode(bytes)
        precondition(recovered.library == source)
        precondition(recovered.version == 2)
        precondition(recovered.library.omittedPrivateAliases == 2)
        precondition(
            !TropLibraryV2RecoveryArchive.isPortableAlias(
                provider: "addon", externalID: "addon:base64-secret"
            )
        )
        precondition(TropLibraryV2RecoveryArchive.isPortableAlias(
            provider: "youtube", externalID: "abc123"
        ))

        let changed = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "Una Canción", with: "Una Canci0n")
        precondition(changed != String(decoding: bytes, as: UTF8.self))
        do {
            _ = try TropLibraryV2RecoveryArchive.decode(Data(changed.utf8))
            preconditionFailure("Corrupt checksum was accepted")
        } catch TropLibraryV2RecoveryError.checksumMismatch {
            // Expected; SHA-256 detects accidental data modification.
        }

        let invalidEntry = TropLibraryV2RecoverySnapshot.PlaylistEntry(
            id: entry, playlistID: playlist,
            recordingID: "a0000000-0000-4000-8000-000000000099",
            position: 0, createdAt: now
        )
        do {
            try TropLibraryV2RecoveryArchive.validate(
                sample(entries: [invalidEntry], sourceAliases: source.aliases)
            )
            preconditionFailure("Dangling playlist reference was accepted")
        } catch TropLibraryV2RecoveryError.invalidData {}

        let leakedAlias = TropLibraryV2RecoverySnapshot.Alias(
            id: alias, itemID: recording, kind: "recording",
            provider: "addon", scope: "global", externalID: "addon:secret"
        )
        do {
            try TropLibraryV2RecoveryArchive.validate(
                sample(entries: source.playlistEntries, sourceAliases: [leakedAlias])
            )
            preconditionFailure("Private addon alias was exported")
        } catch TropLibraryV2RecoveryError.invalidData {}

        do {
            _ = try TropLibraryV2RecoveryArchive.decode(
                Data(count: TropLibraryV2RecoveryArchive.maximumBytes + 1)
            )
            preconditionFailure("Oversized archive was accepted")
        } catch TropLibraryV2RecoveryError.oversized {}

        print("Trop Library V2 metadata archive integrity and privacy checks passed")
    }
}
