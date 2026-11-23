import Foundation

/// Build Eclipse Music resource URLs using a SINGLE RFC 3986 path-segment
/// encoding pass. `URL.appendingPathComponent` percent-encodes a supplied
/// string again, so passing an already-escaped `tidal%3Atrack%3A123` to it
/// produces `tidal%253Atrack%253A123` and breaks provider stream lookups.
enum EclipseAddonURL {
    private static let pathSegmentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// The resource is a trusted, app-defined literal (e.g. stream / album).
    /// The ID is opaque addon data: encode the ENTIRE ID as one path segment,
    /// preserving no embedded slash, query, fragment, or stray percent sign.
    static func resource(
        baseURL: URL,
        resource: String,
        id: String,
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        guard !resource.isEmpty, !id.isEmpty,
              let encodedID = id.addingPercentEncoding(
                withAllowedCharacters: pathSegmentAllowed
              ),
              var components = URLComponents(
                url: baseURL.appendingPathComponent(resource),
                resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        components.percentEncodedPath += "/" + encodedID
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }
}
