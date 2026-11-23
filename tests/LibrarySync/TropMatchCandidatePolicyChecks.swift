import Foundation

@main
struct TropMatchCandidatePolicyChecks {
    static func main() {
        func candidate(
            title: String = "A Lo Mejor",
            artist: String = "Banda MS de Sergio Lizárraga",
            duration: Int = 212,
            album: String? = "No Me Pidas Perdón",
            source: MusicCatalogSource = .addon
        ) -> MusicCatalogTrack {
            var track = MusicCatalogTrack(
                id: MusicCatalogID(source: source, rawValue: "opaque-track"),
                title: title, artist: artist, durationSeconds: duration,
                artworkURL: nil, permalinkURL: nil, isStreamable: true
            )
            track.albumTitle = album
            return track
        }
        func classify(_ track: MusicCatalogTrack) -> TropMatchCandidateKind {
            TropMatchCandidatePolicy.classify(
                title: "A Lo Mejor",
                artist: "Banda MS de Sergio Lizárraga",
                durationSeconds: 212, track: track, requiresLossless: false
            )
        }

        precondition(classify(candidate()) == .exact)
        precondition(classify(candidate(album: nil)) == .exact)
        precondition(classify(candidate(album: "Banda MS En Vivo")) == .review)
        precondition(classify(candidate(title: "A Lo Mejor (Live)")) == .review)
        precondition(classify(candidate(title: "A Lo Mejor (Remix)")) == .review)
        precondition(classify(candidate(title: "A Lo Mejor", duration: 0)) == .review)
        precondition(classify(candidate(title: "A Lo Mejor", duration: 244)) == .review)
        precondition(classify(candidate(title: "A Lo Mejor", duration: 340)) == .unrelated)
        precondition(classify(candidate(artist: "Banda El Recodo")) == .unrelated)
        precondition(classify(candidate(title: "Otra Canción")) == .unrelated)
        precondition(classify(candidate(source: .youtube)) == .unrelated)
        precondition(TropMatchCandidatePolicy.classify(
            title: "A Lo Mejor", artist: "Banda MS de Sergio Lizárraga",
            durationSeconds: 212, track: candidate(source: .audius),
            requiresLossless: true
        ) == .unrelated)
        print("Trop Match checks passed: studio match, live/remix reviews, no lookalikes")
    }
}
