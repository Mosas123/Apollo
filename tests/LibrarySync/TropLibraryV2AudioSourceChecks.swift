import Foundation

@main
struct TropLibraryV2AudioSourceChecks {
    static func main() throws {
        func track(
            source: MusicCatalogSource = .addon,
            title: String = "DILUVIO",
            artist: String = "Rauw Alejandro",
            duration: Int = 213,
            id: String = "track123",
            streamable: Bool = true
        ) -> MusicCatalogTrack {
            MusicCatalogTrack(
                id: MusicCatalogID(source: source, rawValue: id),
                title: title, artist: artist, durationSeconds: duration,
                artworkURL: nil, permalinkURL: nil, isStreamable: streamable
            )
        }
        func allowed(
            _ item: MusicCatalogTrack, lossless: Bool = true
        ) -> Bool {
            TropLibraryV2AudioMatchPolicy.accepts(
                title: "DILUVIO", artist: "Rauw Alejandro",
                durationSeconds: 215, track: item,
                requiresLossless: lossless
            )
        }
        precondition(allowed(track()))
        precondition(allowed(track(source: .qobuz)))
        precondition(!allowed(track(source: .youtube)))
        precondition(!allowed(track(source: .musicbrainz)))
        precondition(!allowed(track(source: .audius)))
        precondition(!allowed(track(source: .jiosaavn)))
        precondition(allowed(track(source: .audius), lossless: false))
        precondition(allowed(track(source: .jiosaavn), lossless: false))
        precondition(!allowed(track(title: "DILUVIO (Live)")))
        precondition(!allowed(track(title: "DILUVIO Remix")))
        precondition(!allowed(track(artist: "Rauw Alejandro Tribute")))
        precondition(!allowed(track(duration: 280)))
        precondition(!allowed(track(duration: 0)))
        precondition(!allowed(track(streamable: false)))
        precondition(!allowed(track(id: "https://sensitive.example/token")))
        precondition(TropLibraryV2AudioMatchPolicy.alias(for:
            track(source: .qobuz))?.provider == "qobuz")
        precondition(TropLibraryV2AudioMatchPolicy.alias(for:
            track(source: .youtube)) == nil)
        print("Library V2 metadata-to-audio policy passed: strict identity, quality and provider guards")
    }
}
