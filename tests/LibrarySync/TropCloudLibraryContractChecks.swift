import Foundation

@main
struct TropCloudLibraryContractChecks {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let id = TropCloudItemID(
            kind: .recording,
            uuid: UUID(uuidString: "72acb25d-245e-4ad6-90c0-49a67a8808c3")!
        )
        precondition(id.storageKey == "trop:recording:72acb25d-245e-4ad6-90c0-49a67a8808c3")
        let legacy = TropCloudSourceAlias(provider: .youtube, externalID: "kT5HSDEF590")!
        let musicbrainz = TropCloudSourceAlias(
            provider: .musicbrainz,
            externalID: "recording:8f9e8c2a-96ac-4d71-8e73-d9a10e8ff05d"
        )!
        precondition(legacy.storageKey == "youtube:kT5HSDEF590")
        precondition(id.storageKey != legacy.storageKey)
        precondition(TropCloudSourceAlias(provider: .youtube, externalID: "") == nil)
        precondition(TropCloudSourceAlias(provider: .addon, externalID: "https://signed/track?token=secret") == nil)
        precondition(TropCloudSourceAlias(provider: .addon, externalID: "track\nheader") == nil)

        let record = TropCloudLibraryRecord(
            id: id, title: "Pvta Luna", artistOrAuthor: "Netro",
            sourceAliases: [legacy, musicbrainz], savedAt: now,
            modifiedAt: now, deletedAt: nil, episodeProgressSeconds: nil
        )
        precondition(record.isValidForCloud && record.isSaved)
        let encoded = try JSONEncoder().encode(record)
        let restored = try JSONDecoder().decode(TropCloudLibraryRecord.self, from: encoded)
        precondition(restored == record)
        precondition(!String(decoding: encoded, as: UTF8.self).contains("https://"))
        precondition(!String(decoding: encoded, as: UTF8.self).contains("localPath"))
        precondition(!String(decoding: encoded, as: UTF8.self).contains("audioData"))

        var duplicate = record
        duplicate.sourceAliases.append(legacy)
        precondition(!duplicate.isValidForCloud)

        var invalidProgress = record
        invalidProgress.episodeProgressSeconds = 50
        precondition(!invalidProgress.isValidForCloud)

        let podcast = TropCloudLibraryRecord(
            id: TropCloudItemID(kind: .podcast), title: "Podcast favorito",
            artistOrAuthor: "Presentador", sourceAliases: [],
            savedAt: now, modifiedAt: now, deletedAt: nil,
            episodeProgressSeconds: nil
        )
        precondition(podcast.isValidForCloud)
        var episode = TropCloudLibraryRecord(
            id: TropCloudItemID(kind: .episode), title: "Episodio 3",
            artistOrAuthor: "Presentador", sourceAliases: [],
            savedAt: now, modifiedAt: now, deletedAt: nil,
            episodeProgressSeconds: 120.5
        )
        precondition(episode.isValidForCloud)
        episode.episodeProgressSeconds = .nan
        precondition(!episode.isValidForCloud)

        for origin in [
            TropCloudSyncOrigin.youtubeRefresh,
            .externalCatalogueRefresh, .cloudImport, .fileImport
        ] {
            precondition(!TropCloudLibrarySyncPolicy.shouldExport(origin: origin))
        }
        precondition(TropCloudLibrarySyncPolicy.shouldExport(origin: .localUserAction))
        var removed = record
        removed.deletedAt = now
        precondition(removed.isValidForCloud && !removed.isSaved)
        precondition(!TropCloudLibrarySyncPolicy.canApplyRemoteRemoval(local: record, incoming: removed))
        precondition(TropCloudLibrarySyncPolicy.canApplyRemoteRemoval(local: removed, incoming: removed))
        precondition(!TropCloudLibrarySyncPolicy.canApplyRemoteRemoval(local: record, incoming: record))

        let playlistID = TropCloudItemID(kind: .playlist)
        let entryID = UUID(uuidString: "3cc6322f-88bb-4447-9007-a64b754f7106")!
        let membership = TropCloudPlaylistEntry(
            entryID: entryID, playlistID: playlistID,
            recordingID: id, position: 0, modifiedAt: now, deletedAt: nil
        )
        precondition(membership.isValidForCloud)
        let membershipData = try JSONEncoder().encode(membership)
        let membershipRoundtrip = try JSONDecoder().decode(
            TropCloudPlaylistEntry.self, from: membershipData
        )
        precondition(membershipRoundtrip == membership)
        var reordered = membership
        reordered.position = 5
        precondition(reordered.entryID == membership.entryID)
        var invalidMembership = membership
        invalidMembership.position = -1
        precondition(!invalidMembership.isValidForCloud)
        invalidMembership = TropCloudPlaylistEntry(
            entryID: entryID, playlistID: id,
            recordingID: id, position: 0, modifiedAt: now, deletedAt: nil
        )
        precondition(!invalidMembership.isValidForCloud)

        let itemKinds: [TropCloudItemKind] = [
            .recording, .album, .artist, .playlist, .podcast, .episode
        ]
        precondition(Set(itemKinds.map(\.rawValue)).count == itemKinds.count)
        // No .download, no cache, no credentials or file bytes in sync schema.
        print("Trop private-cloud metadata-only library contract checks passed")
    }
}
