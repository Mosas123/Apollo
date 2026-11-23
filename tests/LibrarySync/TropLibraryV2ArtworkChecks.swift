import Foundation

// The release selection policy is compiled unchanged with Swift 6 and the
// production text matcher. Network and UI are deliberately absent.
struct ResolvedMetadata: Sendable {
    let title: String
    let artist: String
    let album: String?
    let year: Int?
    let artworkURL: URL?
    let source: String
}

@main
struct TropLibraryV2ArtworkChecks {
    static func main() {
        let secure = URL(string: "https://is1-ssl.mzstatic.com/image.jpg")
        let http = URL(string: "http://example.com/image.jpg")

        func candidate(
            title: String = "DILUVIO",
            artist: String = "Rauw Alejandro",
            source: String = "iTunes",
            url: URL? = URL(string: "https://is1-ssl.mzstatic.com/image.jpg")
        ) -> ResolvedMetadata {
            ResolvedMetadata(
                title: title, artist: artist, album: "Playa Saturno",
                year: 2023, artworkURL: url, source: source
            )
        }

        let resolve: (ResolvedMetadata) -> URL? = {
            TropLibraryV2ArtworkSelectionPolicy.url(
                title: "DILUVIO", artist: "Rauw Alejandro", metadata: $0
            )
        }
        precondition(resolve(candidate()) == secure)
        precondition(resolve(candidate(source: "Deezer")) == secure)
        precondition(resolve(candidate(source: "MusicBrainz")) == secure)
        precondition(resolve(candidate(title: "Different Song")) == nil)
        precondition(resolve(candidate(artist: "Different Artist")) == nil)
        precondition(resolve(candidate(source: "YouTube")) == nil)
        precondition(resolve(candidate(source: "unknown")) == nil)
        precondition(resolve(candidate(url: http)) == nil)
        precondition(resolve(candidate(url: nil)) == nil)
        precondition(resolve(candidate(title: "DILUVIO (Live)")) == nil)
        print("Library V2 artwork policy passed: independent source, exact music, HTTPS")
    }
}
