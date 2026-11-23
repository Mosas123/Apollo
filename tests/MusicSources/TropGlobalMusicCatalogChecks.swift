import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct TropGlobalMusicCatalogChecks {
    static func main() async throws {
        let fixture = """
        {
          "payload": {
            "recordings": [
              {
                "track_name": "Hello Again",
                "artist_name": "Example Artist",
                "recording_mbid": "0fe11cd3-0be4-467b-84fa-0bd524d45d74",
                "release_name": "A Public Release",
                "listen_count": 204
              },
              {
                "track_name": "Hello Again",
                "artist_name": "Example Artist",
                "recording_mbid": "0fe11cd3-0be4-467b-84fa-0bd524d45d74",
                "release_name": "A Public Release",
                "listen_count": 204
              },
              {
                "track_name": "Second Song",
                "artist_name": "Another Artist",
                "recording_mbid": null,
                "release_name": null,
                "listen_count": 60
              },
              {
                "track_name": "Third Song",
                "artist_name": "Example Artist",
                "recording_mbid": "552eeb1f-374d-49d7-b18f-e226a326b9b7",
                "release_name": "A Public Release",
                "listen_count": 110
              },
              {
                "track_name": "Fourth Song",
                "artist_name": "Example Artist",
                "recording_mbid": "e3ee4939-237f-4d20-b4e8-4d3d77ea9f45",
                "release_name": "A Public Release",
                "listen_count": 89
              },
              {
                "track_name": " ",
                "artist_name": "Invalid",
                "recording_mbid": null,
                "release_name": null,
                "listen_count": 30
              }
            ]
          }
        }
        """
        let data = Data(fixture.utf8)
        let transport: TropGlobalMusicCatalog.Transport = { request in
            precondition(request.url?.host == "api.listenbrainz.org")
            precondition(request.url?.path == "/1/stats/sitewide/recordings")
            precondition(request.url?.absoluteString.contains("range=week") == true)
            precondition(request.url?.absoluteString.contains("count=100") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (data, response)
        }
        let catalog = TropGlobalMusicCatalog(transport: transport)
        let items = try await catalog.popularRecordings()
        precondition(items.count == 3)
        precondition(items[0].title == "Hello Again")
        precondition(items[0].album == "A Public Release")
        precondition(items[0].listenCount == 204)
        precondition(items[1].title == "Second Song")
        precondition(items[1].album == nil)
        precondition(items[2].title == "Third Song")
        precondition(items[0].id != items[1].id)
        precondition(!items.contains { $0.title == "Fourth Song" })
        let cached = try await catalog.popularRecordings()
        precondition(cached == items)
        let artistID = "552eeb1f-374d-49d7-b18f-e226a326b9b7"
        let albumID = "e3ee4939-237f-4d20-b4e8-4d3d77ea9f45"
        let artistFixture = """
        {"payload":{"artists":[
          {"artist_mbid":"\(artistID)","artist_name":"Example Artist","listen_count":100},
          {"artist_mbid":null,"artist_name":"Unverified Artist","listen_count":99}
        ]}}
        """
        let albumFixture = """
        {"payload":{"release_groups":[
          {"release_group_mbid":"\(albumID)","release_group_name":"Album One",
           "artist_name":"Example Artist","listen_count":99},
          {"release_group_mbid":"","release_group_name":"Unverified",
           "artist_name":"Example Artist","listen_count":98}
        ]}}
        """
        let expanded = TropGlobalMusicCatalog(transport: { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: nil
                  ) else { throw TropGlobalCatalogError.invalidResponse }
            precondition(url.host == "api.listenbrainz.org")
            precondition(url.absoluteString.contains("range=week"))
            switch url.path {
            case "/1/stats/sitewide/artists":
                return (Data(artistFixture.utf8), response)
            case "/1/stats/sitewide/release-groups":
                return (Data(albumFixture.utf8), response)
            default:
                preconditionFailure("Unexpected ListenBrainz feed")
            }
        })
        let publicArtists = try await expanded.popularArtists()
        precondition(publicArtists.count == 1)
        precondition(publicArtists[0].id == artistID)
        let publicAlbums = try await expanded.popularReleaseGroups()
        precondition(publicAlbums.count == 1)
        precondition(publicAlbums[0].id == albumID)
        precondition(publicAlbums[0].title == "Album One")
        print("Public global music: tracks, artist identities and release groups passed")
    }
}
