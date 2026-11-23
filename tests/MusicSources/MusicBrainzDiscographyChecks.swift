import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct MusicBrainzDiscographyChecks {
    static func main() async throws {
        let artist = "Example Singer"
        let groupID = "fe551de1-0c1e-42f6-a32d-a8b69a77329d"
        let releaseID = "c03e7f7f-52db-4a7d-9d6e-9da99799c339"
        let recordID1 = "a5b0b49e-f82c-488d-8661-c4cb4b495e72"
        let recordID2 = "dd65034a-7562-4fbd-baa0-6bab63d7d25f"
        let groupJSON = """
        {"release-groups":[
          {"id":"\(groupID)","title":"Example Album","primary-type":"Album",
           "artist-credit":[{"name":"\(artist)"}]}
        ]}
        """
        let releasesJSON = """
        {"releases":[{"id":"\(releaseID)","status":"Official"}]}
        """
        let tracksJSON = """
        {"media":[{"tracks":[
          {"number":"1","length":203900,
           "artist-credit":[{"name":"\(artist)"}],
           "recording":{"id":"\(recordID1)","title":"Opening Song","length":203000}},
          {"number":"2",
           "artist-credit":[{"name":"\(artist)"}],
           "recording":{"id":"\(recordID2)","title":"Second Song","length":191000}}
        ]}]}
        """
        let client = MusicBrainzIdentityCatalog(
            transport: { request in
                guard let url = request.url,
                      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let http = HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: nil,
                        headerFields: nil
                      ) else { throw MusicBrainzCatalogError.invalidRequest }
                precondition(url.host == "musicbrainz.org")
                let params = Dictionary(uniqueKeysWithValues:
                    (parts.queryItems ?? []).compactMap { pair in
                        pair.value.map { (pair.name, $0) }
                    })
                precondition(params["fmt"] == "json")
                switch url.path {
                case "/ws/2/release-group":
                    precondition(params["query"] == "artist:\"Example Singer\"")
                    return (Data(groupJSON.utf8), http)
                case "/ws/2/release":
                    precondition(params["release-group"] == groupID)
                    return (Data(releasesJSON.utf8), http)
                case "/ws/2/release/\(releaseID)":
                    precondition(params["inc"] == "recordings+artist-credits")
                    return (Data(tracksJSON.utf8), http)
                default:
                    preconditionFailure("Unexpected MusicBrainz API route")
                }
            },
            limiter: MusicBrainzRequestLimiter(interval: .zero)
        )
        let albums = try await client.searchAlbumsByArtist(artist: artist)
        precondition(albums.count == 1)
        precondition(albums[0].id.mbid == groupID)
        let tracks = try await client.albumTracks(releaseGroupID: groupID)
        precondition(tracks.count == 2)
        precondition(tracks[0].id == recordID1)
        precondition(tracks[0].position == 1)
        precondition(tracks[0].title == "Opening Song")
        precondition(tracks[0].durationSeconds == 203)
        precondition(tracks[0].artist == artist)
        precondition(tracks[1].id == recordID2)
        precondition(tracks[1].position == 2)
        precondition(tracks[1].durationSeconds == 191)
        precondition(try await client.albumTracks(releaseGroupID: "invalid") == [])
        print("Independent artist discography and ordered album tracklist passed")
    }
}
