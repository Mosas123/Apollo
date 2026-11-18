import Foundation

struct AddonPlaybackRef: Codable, Sendable, Equatable {
    let k: String
    let t: String
    let i: String
}

enum AddonPlaybackID {
    static let prefix = "addon:"

    static func encode(key: String, type: String, id: String) -> String {
        let ref = AddonPlaybackRef(k: key, t: type, i: id)
        let data = (try? JSONEncoder().encode(ref)) ?? Data()
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ raw: String) -> AddonPlaybackRef? {
        guard raw.hasPrefix(prefix) else { return nil }
        var base = String(raw.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        guard let data = Data(base64Encoded: base) else { return nil }
        return try? JSONDecoder().decode(AddonPlaybackRef.self, from: data)
    }
}

enum MusicAddonClientError: Error, Equatable {
    case unsupportedProtocol
    case invalidURL
    case noResults
    case noStream
}

struct AddonTrack: Sendable, Equatable {
    let installationKey: String
    let type: String
    let id: String
    let title: String
    let poster: URL?
    let detail: String?
}

struct AddonStream: Sendable {
    enum Kind: Sendable {
        case url(URL)
        case youtube(String)
    }
    let kind: Kind
    let mimeType: String
    let bitrate: Int
    /// "Lossless" / "High" / "Standard" derived from the stream metadata.
    let qualityTier: String
}

/// Read-only client for Stremio music addons. It only calls `catalog/.../search`
/// and `stream/...` and never executes provider code.
actor MusicAddonClient {
    let installation: MusicAddonInstallation
    private let baseURL: URL
    private let catalogTypes: [String]
    private let searchCatalogs: [StremioDescriptor.Catalog]

    init(installation: MusicAddonInstallation) throws {
        guard installation.manifest.protocolKind == .stremio,
              let descriptor = installation.manifest.stremio else {
            throw MusicAddonClientError.unsupportedProtocol
        }
        self.installation = installation
        self.baseURL = installation.manifestURL.deletingLastPathComponent()
        let preferred = ["track", "song", "music", "audio"]
        let available = Set(descriptor.types.map { $0.lowercased() })
        let types = preferred.filter { available.contains($0) }
        let finalTypes = types.isEmpty ? descriptor.types.map { $0.lowercased() } : types
        self.catalogTypes = finalTypes
        let searchable = descriptor.catalogs.filter { catalog in
            catalog.extra?.contains { $0.name.lowercased() == "search" } == true
        }
        let preferredCatalogs = searchable.filter { finalTypes.contains($0.type.lowercased()) }
        self.searchCatalogs = preferredCatalogs.isEmpty ? searchable : preferredCatalogs
    }

    var installationKey: String { installation.key }
    var name: String { installation.manifest.name }

    func search(_ query: String, limit: Int = 20) async throws -> [AddonTrack] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !searchCatalogs.isEmpty else { return [] }
        var tracks: [AddonTrack] = []
        var seen = Set<String>()

        for catalog in searchCatalogs.prefix(3) {
            guard let encoded = term.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            ) else { continue }
            let url = baseURL
                .appendingPathComponent("catalog")
                .appendingPathComponent(catalog.type)
                .appendingPathComponent(catalog.id)
                .appendingPathComponent("search=\(encoded).json")
            guard let data = await fetch(url),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let root = object as? [String: Any],
                  let metas = root["metas"] as? [[String: Any]] else { continue }
            for meta in metas {
                guard let id = meta["id"] as? String,
                      let name = meta["name"] as? String,
                      !name.isEmpty else { continue }
                let type = (meta["type"] as? String) ?? catalog.type
                let key = "\(type)|\(id)"
                guard seen.insert(key).inserted else { continue }
                let posterString = (meta["poster"] as? String) ?? (meta["logo"] as? String)
                let detail = (meta["description"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                tracks.append(AddonTrack(
                    installationKey: installation.key,
                    type: type,
                    id: id,
                    title: name,
                    poster: posterString.flatMap(URL.init(string:)),
                    detail: (detail?.isEmpty == false) ? detail : nil
                ))
                if tracks.count >= limit { return tracks }
            }
        }
        return tracks
    }

    func resolveStream(type: String, id: String) async throws -> AddonStream {
        let url = baseURL
            .appendingPathComponent("stream")
            .appendingPathComponent(type)
            .appendingPathComponent("\(id).json")
        guard let data = await fetch(url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let streams = root["streams"] as? [[String: Any]] else {
            throw MusicAddonClientError.noStream
        }
        for stream in streams {
            if let ytId = stream["ytId"] as? String, !ytId.isEmpty {
                return AddonStream(kind: .youtube(ytId), mimeType: "audio/mp4", bitrate: 0, qualityTier: "Standard")
            }
            let raw = (stream["url"] as? String) ?? (stream["externalUrl"] as? String)
            guard let raw, let streamURL = URL(string: raw),
                  let scheme = streamURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { continue }
            let hints = Self.describe(stream)
            let quality = Self.quality(from: hints, url: streamURL)
            return AddonStream(
                kind: .url(streamURL),
                mimeType: quality.mime,
                bitrate: quality.bitrate,
                qualityTier: quality.tier
            )
        }
        throw MusicAddonClientError.noStream
    }

    // MARK: - Helpers

    private func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return data
    }

    private static func describe(_ stream: [String: Any]) -> String {
        let parts = [
            stream["name"] as? String,
            stream["description"] as? String,
            stream["title"] as? String
        ].compactMap { $0 }
        return parts.joined(separator: " ").lowercased()
    }

    private static func quality(from text: String, url: URL) -> (tier: String, mime: String, bitrate: Int) {
        let ext = url.pathExtension.lowercased()
        let haystack = (text + " " + url.absoluteString.lowercased())
        if ext == "flac" || haystack.contains("flac") || haystack.contains("lossless") {
            return ("Lossless", "audio/flac", 0)
        }
        if haystack.contains("hi-res") || haystack.contains("hires") || haystack.contains("24bit") || haystack.contains("24-bit") {
            return ("Lossless", ext == "flac" ? "audio/flac" : "audio/mp4", 0)
        }
        let bitrate: Int
        if let match = haystack.range(of: #"(320|256|192)\s*kbps"#, options: .regularExpression) {
            let digits = haystack[match].prefix { $0.isNumber }
            bitrate = (Int(digits) ?? 0) * 1000
        } else {
            bitrate = 0
        }
        let tier = bitrate >= 160_000 ? "High" : "Standard"
        switch ext {
        case "mp3": return (tier, "audio/mpeg", bitrate)
        case "aac": return (tier, "audio/aac", bitrate)
        case "m4a", "mp4": return (tier, "audio/mp4", bitrate)
        case "ogg", "opus": return (tier, "audio/ogg", bitrate)
        default: return (tier, "audio/mpeg", bitrate)
        }
    }
}
