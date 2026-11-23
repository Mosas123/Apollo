import Foundation

@main
struct TropLibraryV2PrelinkPolicyChecks {
    static func main() throws {
        func candidate(
            source: MusicCatalogSource = .addon,
            id: String,
            title: String = "A Lo Mejor",
            artist: String = "Banda MS de Sergio Lizárraga",
            duration: Int = 212,
            album: String? = "No Me Pidas Perdón"
        ) -> MusicCatalogTrack {
            var track = MusicCatalogTrack(
                id: MusicCatalogID(source: source, rawValue: id),
                title: title, artist: artist, durationSeconds: duration,
                artworkURL: nil, permalinkURL: nil,
                isStreamable: true
            )
            track.albumTitle = album
            return track
        }

        let addon = candidate(id: "addon-studio")
        let secondAddon = candidate(id: "addon-studio-other")
        let qobuz = candidate(source: .qobuz, id: "124")
        let audius = candidate(source: .audius, id: "D3")
        let jiosaavn = candidate(source: .jiosaavn, id: "J4")
        let live = candidate(id: "addon-live", album: "Banda MS En Vivo")
        let remix = candidate(id: "addon-remix", title: "A Lo Mejor (Remix)")
        let wrongArtist = candidate(id: "wrong-artist", artist: "Other Artist")
        let wrongDuration = candidate(id: "too-long", duration: 305)
        let noDuration = candidate(id: "no-duration", duration: 0)
        let youtube = candidate(source: .youtube, id: "DCEVC_sr5Go")
        let query = [
            live, remix, wrongArtist, wrongDuration, noDuration, youtube,
            addon, addon, secondAddon, qobuz, audius, jiosaavn
        ]

        func eligible(
            existing: [TropLibraryV2SourceAlias] = [],
            items: [MusicCatalogTrack] = [],
            duration: Int = 212,
            artist: String? = "Banda MS de Sergio Lizárraga"
        ) -> [MusicCatalogTrack] {
            TropLibraryV2PrelinkPolicy.eligibleNewLinks(
                title: "A Lo Mejor", artist: artist,
                durationSeconds: duration,
                existingAliases: existing,
                candidates: items
            )
        }

        precondition(
            TropLibraryV2PrelinkPolicy.hasSufficientMetadata(
                title: "A Lo Mejor", artist: "Banda MS",
                durationSeconds: 212
            )
        )
        precondition(
            !TropLibraryV2PrelinkPolicy.hasSufficientMetadata(
                title: "A Lo Mejor", artist: nil, durationSeconds: 212
            )
        )
        precondition(
            !TropLibraryV2PrelinkPolicy.hasSufficientMetadata(
                title: "A Lo Mejor", artist: "Banda MS", durationSeconds: 0
            )
        )
        precondition(eligible(items: query).map(\.id) == [addon.id, secondAddon.id])
        precondition(eligible(items: [live, remix, noDuration]).isEmpty)
        precondition(eligible(items: [wrongArtist, wrongDuration, youtube]).isEmpty)
        precondition(eligible(items: [addon], duration: 0).isEmpty)
        precondition(eligible(items: [addon], artist: nil).isEmpty)

        let knownYouTube = try TropLibraryV2SourceAlias(
            provider: "youtube", externalID: "DCEVC_sr5Go"
        )
        let knownAddon = try TropLibraryV2SourceAlias(
            provider: "addon", externalID: "addon-studio"
        )
        let knownQobuz = try TropLibraryV2SourceAlias(
            provider: "qobuz", externalID: "124"
        )
        let approvedLive = try TropLibraryV2SourceAlias(
            provider: "addon", scope: "user-approved-alt",
            externalID: "addon-live"
        )
        precondition(eligible(existing: [knownYouTube], items: [qobuz]).map(\.id) == [qobuz.id])
        precondition(eligible(existing: [knownAddon], items: [addon, qobuz]).map(\.id) == [qobuz.id])
        precondition(
            eligible(existing: [knownAddon, knownQobuz], items: [secondAddon, audius])
                .map(\.id) == [secondAddon.id]
        )
        precondition(
            eligible(existing: [knownAddon, knownQobuz, knownYouTube], items: [secondAddon])
                .map(\.id) == [secondAddon.id]
        )
        precondition(
            eligible(existing: [knownAddon, knownQobuz, knownYouTube,
                                knownAddon], items: [secondAddon]).isEmpty
        )
        precondition(
            eligible(existing: [approvedLive], items: [addon, qobuz])
                .map(\.id) == [addon.id, qobuz.id]
        )
        precondition(TropLibraryV2PrelinkPolicy.maximumLinksPerPass == 2)
        precondition(TropLibraryV2PrelinkPolicy.visibleLibraryBudget <= 8)
        precondition(TropLibraryV2PrelinkPolicy.maximumQueuedRecordings <= 24)
        print(
            "Library V2 prelink passed: saved-only metadata, exact editions, "
                + "multiple providers, bounded requests and no duplicate aliases"
        )
    }
}
