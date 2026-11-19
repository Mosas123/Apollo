import Foundation

/// Detects how a station is delivered before playback: HLS, direct ICY
/// (MP3/AAC with `icy-metaint`) or an exotic container that must go through
/// FFmpeg. The answer is a MIME hint for Apolo, cached per URL.
enum RadioTransport: String, Sendable {
    case hls
    case icy
    case ffmpeg
    case direct
}

actor RadioTransportResolver {
    static let shared = RadioTransportResolver()

    private struct Entry: Sendable {
        let transport: RadioTransport
        let hint: String?
        let at: Date
    }

    private var cache: [String: Entry] = [:]
    private var inFlight: [String: Task<Entry, Never>] = [:]
    private let ttl: TimeInterval = 900

    /// Returns the Apolo `sourceMIMEType` hint for this station.
    func hint(for station: RadioStation) async -> String? {
        guard let raw = station.streamURL, let url = URL(string: raw) else {
            return station.apoloMIMEHint
        }
        if let cached = cache[raw], Date().timeIntervalSince(cached.at) < ttl {
            return cached.hint
        }
        if let running = inFlight[raw] {
            return await running.value.hint
        }
        let task = Task { [station, url, raw] in
            await self.classify(station: station, url: url, raw: raw)
        }
        inFlight[raw] = task
        let entry = await task.value
        inFlight[raw] = nil
        cache[raw] = entry
        return entry.hint
    }

    private func classify(station: RadioStation, url: URL, raw: String) async -> Entry {
        if station.isHLS || url.pathExtension.lowercased() == "m3u8" {
            return Entry(transport: .hls, hint: "application/vnd.apple.mpegurl", at: Date())
        }
        let codec = (station.codec ?? "").uppercased()
        if codec.contains("OPUS") || codec.contains("OGG") || codec.contains("VORBIS") || codec.contains("FLAC") {
            return Entry(transport: .ffmpeg, hint: station.apoloMIMEHint, at: Date())
        }
        if let probed = await probe(url: url) {
            return Entry(transport: probed.transport, hint: probed.hint ?? station.apoloMIMEHint, at: Date())
        }
        return Entry(transport: .direct, hint: station.apoloMIMEHint, at: Date())
    }

    /// Sends `Icy-MetaData: 1` and inspects only the response headers; the
    /// async byte stream is released right away so an endless radio body is
    /// never consumed.
    private func probe(url: URL) async -> (transport: RadioTransport, hint: String?)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        request.setValue("Thrum/1.0", forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await URLSession.shared.bytes(for: request),
              let http = response as? HTTPURLResponse,
              (200...399).contains(http.statusCode) else {
            return nil
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("mpegurl") || contentType.contains("m3u") {
            return (.hls, "application/vnd.apple.mpegurl")
        }
        let metaint = http.value(forHTTPHeaderField: "icy-metaint") ?? ""
        if !metaint.isEmpty, metaint != "0" {
            return (.icy, "application/x-icy")
        }
        return (.direct, nil)
    }
}
