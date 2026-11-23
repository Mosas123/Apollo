import Foundation

@main
struct EclipseAddonURLChecks {
    static func main() {
        let base = URL(string: "https://example.invalid/fixture-tenant/")!

        let tidal = EclipseAddonURL.resource(
            baseURL: base,
            resource: "stream",
            id: "tidal:track:12345",
            queryItems: [
                URLQueryItem(name: "atmos", value: "false"),
                URLQueryItem(name: "quality", value: "lossless")
            ]
        )
        precondition(
            tidal?.absoluteString ==
                "https://example.invalid/fixture-tenant/stream/tidal%3Atrack%3A12345?atmos=false&quality=lossless",
            "Eclipse/Tidal track ID must be encoded EXACTLY once"
        )
        precondition(tidal?.absoluteString.contains("%253A") == false)

        let pathID = EclipseAddonURL.resource(
            baseURL: base,
            resource: "album",
            id: "album/a b?c#d"
        )
        precondition(
            pathID?.absoluteString ==
                "https://example.invalid/fixture-tenant/album/album%2Fa%20b%3Fc%23d",
            "Opaque addon IDs may never inject path/query/fragment segments"
        )

        let percentID = EclipseAddonURL.resource(
            baseURL: base, resource: "stream", id: "abc%2Fdef"
        )
        precondition(
            percentID?.absoluteString ==
                "https://example.invalid/fixture-tenant/stream/abc%252Fdef",
            "Literal percent signs in the ORIGINAL ID must be encoded once"
        )

        let regular = EclipseAddonURL.resource(
            baseURL: base, resource: "stream", id: "392775794"
        )
        precondition(
            regular?.absoluteString ==
                "https://example.invalid/fixture-tenant/stream/392775794",
            "Simple IDs, including NullBeat IDs, remain unchanged"
        )
        precondition(EclipseAddonURL.resource(baseURL: base, resource: "stream", id: "") == nil)

        print("Eclipse URL encoding regression checks passed")
    }
}
