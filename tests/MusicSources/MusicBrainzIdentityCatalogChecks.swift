import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mock-only checks; no calls to MusicBrainz servers, accounts or stream APIs.
@main
struct MusicBrainzIdentityCatalogChecks {
    static func main() async throws {
        let mbid = "8f9e8c2a-96ac-4d71-8e73-d9a10e8ff05d"
        let artistID = "c1bbd9b9-88bf-4a73-a421-0f8849a0fe42"
        let albumID = "ea7b653b-4f83-43ed-b86e-1051d81df3bb"
        let recordingJSON = """
        {"recordings":[
          {"id":"\(mbid)","title":"Canción & Jazz","length":214980,"score":100,
           "artist-credit":[{"name":"Artista Uno"}," feat. ",{"name":"Artista Dos"}],
           "isrcs":["USRC17607839","bad"]},
          {"id":"\(mbid)","title":"Duplicated","artist-credit":[{"name":"Other"}]},
          {"id":"4cbf9ef7-91fc-41fe-aa9a-b9cde93e4310","title":"Music video",
           "video":true,"artist-credit":[{"name":"Artista Uno"}]},
          {"id":"not-an-mbid","title":"Invalid","artist-credit":[{"name":"Artista Uno"}]},
          {"id":"7cd554d5-c887-4b90-9c1a-56d07407d15d","title":"Unknown credit"}
        ]}
        """
        let artistJSON = """
        {"artists":[
          {"id":"\(artistID)","name":"Artista Uno","disambiguation":"Cuban singer","score":95},
          {"id":"\(artistID)","name":"Duplicate"},
          {"id":"oops","name":"Invalid"}
        ]}
        """
        let albumJSON = """
        {"release-groups":[
          {"id":"\(albumID)","title":"Álbum Ñ","primary-type":"Album",
           "first-release-date":"2024-06-02","score":98,
           "artist-credit":[{"name":"Artista Uno"}]},
          {"id":"oops","title":"Invalid","artist-credit":[{"name":"Artist"}]},
          {"id":"5b544a09-5235-4dbd-9639-283561d484b1","title":"No credits"}
        ]}
        """
        let limiter = MusicBrainzRequestLimiter(interval: .zero)
        let client = MusicBrainzIdentityCatalog(
            transport: { request in
                guard let url = request.url,
                      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let response = HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: nil, headerFields: nil
                      ) else { throw MusicBrainzCatalogError.invalidRequest }
                precondition(url.scheme == "https" && url.host == "musicbrainz.org")
                precondition(request.value(forHTTPHeaderField: "User-Agent")?.contains("Trop/") == true)
                precondition(request.value(forHTTPHeaderField: "Accept") == "application/json")
                let params = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).compactMap { item in
                    item.value.map { (item.name, $0) }
                })
                precondition(params["fmt"] == "json")
                precondition(params["limit"] == "50")
                switch url.path {
                case "/ws/2/recording":
                    precondition(params["query"] == "recording:\"Canción & Jazz\" AND artist:\"Artista Uno\"")
                    return (Data(recordingJSON.utf8), response)
                case "/ws/2/artist":
                    precondition(params["query"] == "artist:\"Artista Uno\"")
                    return (Data(artistJSON.utf8), response)
                case "/ws/2/release-group":
                    precondition(params["query"] == "releasegroup:\"Álbum Ñ\" AND artist:\"Artista Uno\"")
                    return (Data(albumJSON.utf8), response)
                default:
                    preconditionFailure("Unexpected endpoint")
                }
            },
            limiter: limiter
        )

        let recordings = try await client.searchRecordings(
            title: "  Canción & Jazz  ", artist: " Artista Uno ", limit: 500
        )
        precondition(recordings.count == 1, "Never promote video or ambiguous rows")
        let recording = recordings[0]
        precondition(recording.id.storageKey == "musicbrainz:recording:\(mbid)")
        precondition(recording.id.catalogID.storageKey == recording.id.storageKey)
        precondition(MusicCatalogID(storageKey: recording.id.storageKey) == recording.id.catalogID)
        precondition(recording.artist == "Artista Uno feat. Artista Dos")
        precondition(recording.durationSeconds == 214 && recording.score == 100)
        precondition(recording.isrcs == ["USRC17607839"])
        precondition(!MusicPlaybackIdentity.isYouTube(recording.id.storageKey))
        precondition(MusicBrainzEntityID(kind: .recording, mbid: "invalid") == nil)
        precondition(MusicBrainzEntityID(kind: .recording, mbid: mbid)?.storageKey
            != MusicBrainzEntityID(kind: .artist, mbid: mbid)?.storageKey)

        let artists = try await client.searchArtists(query: "Artista Uno", limit: 500)
        precondition(artists.count == 1)
        precondition(artists[0].id.storageKey == "musicbrainz:artist:\(artistID)")
        precondition(artists[0].disambiguation == "Cuban singer")

        let albums = try await client.searchAlbums(
            title: "Álbum Ñ", artist: "Artista Uno", limit: 500
        )
        precondition(albums.count == 1)
        precondition(albums[0].id.storageKey == "musicbrainz:release-group:\(albumID)")
        precondition(albums[0].primaryType == "Album")
        precondition(albums[0].firstReleaseDate == "2024-06-02")

        // Empty queries must not consume the network budget or emit a request.
        let emptyRecordings = try await client.searchRecordings(title: "   ", artist: "")
        let emptyArtists = try await client.searchArtists(query: "")
        let emptyAlbums = try await client.searchAlbums(title: "", artist: "")
        precondition(emptyRecordings.isEmpty && emptyArtists.isEmpty && emptyAlbums.isEmpty)

        let throttled = MusicBrainzIdentityCatalog(
            transport: { request in
                guard let url = request.url,
                      let http = HTTPURLResponse(
                        url: url, statusCode: 429, httpVersion: nil, headerFields: nil
                      ) else { throw MusicBrainzCatalogError.invalidRequest }
                return (Data(), http)
            },
            limiter: limiter
        )
        do {
            _ = try await throttled.searchArtists(query: "test")
            preconditionFailure("Do not swallow HTTP 429")
        } catch MusicBrainzCatalogError.httpStatus(429) {}

        let tooLarge = MusicBrainzIdentityCatalog(
            transport: { request in
                guard let url = request.url,
                      let http = HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: nil, headerFields: nil
                      ) else { throw MusicBrainzCatalogError.invalidRequest }
                return (Data(repeating: 65, count: 2 * 1024 * 1024 + 1), http)
            },
            limiter: limiter
        )
        do {
            _ = try await tooLarge.searchArtists(query: "test")
            preconditionFailure("Reject oversized JSON")
        } catch MusicBrainzCatalogError.oversizedResponse {}

        // Even separate clients share a gate; concurrent requests reserve
        // separate slots before sleeping (without touching the real API).
        let sharedGate = MusicBrainzRequestLimiter(interval: .milliseconds(140))
        let start = ContinuousClock.now
        async let first = sharedGate.waitForSlot()
        async let second = sharedGate.waitForSlot()
        _ = try await (first, second)
        precondition(start.duration(to: .now) >= .milliseconds(125))

        print("MusicBrainz independent catalogue checks passed")
    }
}
