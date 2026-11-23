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
            precondition(request.url?.absoluteString.contains("count=25") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (data, response)
        }
        let catalog = TropGlobalMusicCatalog(transport: transport)
        let items = try await catalog.popularRecordings()
        precondition(items.count == 2)
        precondition(items[0].title == "Hello Again")
        precondition(items[0].album == "A Public Release")
        precondition(items[0].listenCount == 204)
        precondition(items[1].title == "Second Song")
        precondition(items[1].album == nil)
        precondition(items[0].id != items[1].id)
        let cached = try await catalog.popularRecordings()
        precondition(cached == items)
        print("Global metadata discovery: public source, validation and cache passed")
    }
}
