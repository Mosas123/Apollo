import Foundation

@main
struct StationPolicyChecks {
    static func main() {
        tagSelectionIsDeterministic()
        diversityCapsAreEnforced()
        emptyDimensionsNeverBlock()
        print("StationPolicyChecks passed")
    }

    private static func tagSelectionIsDeterministic() {
        let candidates = MusicBrainzTagPolicy.candidates(
            genres: ["Salsa", "Latin"],
            tags: [
                (name: "salsa", count: 9),
                (name: "latin", count: 12),
                (name: "Seen Live", count: 100),
                (name: "", count: 5)
            ]
        )
        precondition(MusicBrainzTagPolicy.select(candidates, limit: 3) == ["Latin", "Salsa"])
        precondition(MusicBrainzTagPolicy.select(candidates, limit: 0) == [])
        precondition(MusicBrainzTagPolicy.select([], limit: 3) == [])

        let fallback = MusicBrainzTagPolicy.candidates(
            genres: ["reggaeton"],
            tags: [
                (name: "reggaeton", count: 20),
                (name: "trap latino", count: 7),
                (name: "latin", count: 7)
            ]
        )
        precondition(MusicBrainzTagPolicy.select(fallback, limit: 2) == ["reggaeton", "latin"])
    }

    private static func diversityCapsAreEnforced() {
        precondition(StationDiversityPolicy.caps(style: "similar", maxPerArtist: 0, maxPerAlbum: 0) == (3, 2))
        precondition(StationDiversityPolicy.caps(style: "variety", maxPerArtist: 0, maxPerAlbum: 0) == (1, 1))
        precondition(StationDiversityPolicy.caps(style: "deepCuts", maxPerArtist: 0, maxPerAlbum: 0) == (2, 2))
        precondition(StationDiversityPolicy.caps(style: "similar", maxPerArtist: 5, maxPerAlbum: 4) == (5, 4))

        var policy = StationDiversityPolicy(maxPerArtist: 1, maxPerAlbum: 1)
        precondition(policy.select(artistKey: "a", albumKey: "x"))
        precondition(!policy.select(artistKey: "a", albumKey: "y"))
        precondition(!policy.select(artistKey: "b", albumKey: "x"))
        precondition(policy.select(artistKey: "b", albumKey: "y"))

        var sequence = StationDiversityPolicy(maxPerArtist: 1, maxPerAlbum: 1)
        let candidates = [
            ("a", "x"), ("a", "y"), ("b", "x"), ("b", "y"),
            ("c", "z"), ("c", "z"), ("d", "w")
        ]
        let accepted = candidates.enumerated().compactMap { index, candidate in
            sequence.select(artistKey: candidate.0, albumKey: candidate.1) ? index : nil
        }
        precondition(accepted == [0, 3, 4, 6])
    }

    private static func emptyDimensionsNeverBlock() {
        var policy = StationDiversityPolicy(maxPerArtist: 1, maxPerAlbum: 1)
        for _ in 0..<3 {
            precondition(policy.select(artistKey: "", albumKey: ""))
        }
        // An empty artist still counts the album, and vice versa.
        precondition(policy.select(artistKey: "", albumKey: "same"))
        precondition(!policy.select(artistKey: "new", albumKey: "same"))
        precondition(policy.select(artistKey: "new", albumKey: "other"))
    }
}
