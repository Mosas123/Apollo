import Foundation
import Observation

enum MusicAddonDownloadError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case oversizedManifest
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a valid HTTPS addon manifest URL."
        case .invalidResponse: return "The server did not return a valid manifest response."
        case .oversizedManifest: return "The manifest exceeds the 64 KB size limit."
        case .requestFailed: return "The manifest could not be fetched. Check the URL and connection."
        }
    }
}

private final class MusicAddonRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let baseDomain: String

    init(baseDomain: String) {
        self.baseDomain = baseDomain
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Follow only HTTPS redirects inside the same registrable domain
        // (e.g. stream -> stream1). Never jump to another host or HTTP.
        guard let target = request.url,
              target.scheme?.lowercased() == "https",
              MusicAddonManifestDownloader.registrableDomain(target.host) == baseDomain else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

/// Only reads a small declarative JSON manifest. It never sends cookies,
/// executes provider code, calls addon endpoints, or receives audio streams.
/// Separate address/DNS checks are required before dynamic addon requests.
struct MusicAddonManifestDownloader: Sendable {
    func download(from requestedURL: URL) async throws -> (Data, URL) {
        guard let url = MusicAddonPackage.validatedManifestURL(requestedURL) else {
            throw MusicAddonDownloadError.invalidURL
        }

        guard let baseDomain = Self.registrableDomain(url.host) else {
            throw MusicAddonDownloadError.invalidURL
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 7
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let stream: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (stream, response) = try await session.bytes(
                for: request, delegate: MusicAddonRedirectPolicy(baseDomain: baseDomain)
            )
        } catch {
            throw MusicAddonDownloadError.requestFailed
        }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let finalURL = http.url,
              Self.registrableDomain(finalURL.host) == baseDomain else {
            throw MusicAddonDownloadError.invalidResponse
        }
        if http.expectedContentLength > 64 * 1024 {
            throw MusicAddonDownloadError.oversizedManifest
        }
        var data = Data()
        do {
            for try await byte in stream {
                data.append(byte)
                guard data.count <= 64 * 1024 else {
                    throw MusicAddonDownloadError.oversizedManifest
                }
            }
        } catch let error as MusicAddonDownloadError {
            throw error
        } catch {
            throw MusicAddonDownloadError.requestFailed
        }
        guard !data.isEmpty else { throw MusicAddonDownloadError.invalidResponse }
        return (data, finalURL)
    }

    static func registrableDomain(_ host: String?) -> String? {
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return host }
        let twoPartSuffixes: Set<String> = ["co.uk", "com.br", "com.au", "co.jp", "co.nz", "com.mx", "co.in"]
        let suffix = labels.suffix(2).joined(separator: ".")
        if twoPartSuffixes.contains(suffix), labels.count >= 3 {
            return labels.suffix(3).joined(separator: ".")
        }
        return labels.suffix(2).joined(separator: ".")
    }
}

/// Persists *only validated manifest metadata and user enablement*. There
/// are no API keys here. A real runtime/network adapter is NOT installed.
@MainActor
@Observable
final class MusicAddonsStore {
    static let shared = MusicAddonsStore()

    // An offline-only example to test the interface and registry. No catalog
    // requests or playback are made for this reserved example domain.
    static let sampleURL = URL(string: "https://demo.trop.example/manifest.json")!
    static let sampleJSON = """
        {
          "schemaVersion": 1,
          "id": "trop.demo",
          "name": "Trop Demo (No Audio)",
          "version": "1.0.0",
          "description": "Offline sample for testing the addon manager. No searches or audio are available.",
          "capabilities": ["search", "lyrics"],
          "endpoints": {"search": "/demo/search", "lyrics": "/demo/lyrics"}
        }
        """

    static func isSample(_ entry: MusicAddonInstallation) -> Bool {
        entry.manifestURL == sampleURL && entry.manifest.id == "trop.demo"
    }

    private var registry = MusicAddonRegistry()
    private let storageKey = "trop.musicAddons.declarative.v1"

    var installations: [MusicAddonInstallation] { registry.installations }

    var enabledStremioInstallations: [MusicAddonInstallation] {
        installations.filter { $0.isEnabled && $0.manifest.protocolKind == .stremio }
    }

    func installation(key: String) -> MusicAddonInstallation? {
        installations.first { $0.key == key && $0.isEnabled }
    }
    var enabledCount: Int { installations.filter(\.isEnabled).count }
    var streamCapabilityCount: Int {
        installations.filter { $0.manifest.capabilities.contains(.stream) }.count
    }

    private init() {
        restoreValidatedEntries()
        syncAddonAvailability()
    }

    func install(_ data: Data, from url: URL) throws {
        try registry.install(data: data, from: url)
        save()
    }

    func installSample() throws {
        try install(Data(Self.sampleJSON.utf8), from: Self.sampleURL)
    }

    func setEnabled(_ enabled: Bool, key: String) throws {
        try registry.setEnabled(enabled, for: key)
        save()
    }

    func remove(key: String) throws {
        try registry.remove(key: key)
        save()
    }

    func move(from source: Int, to target: Int) {
        registry.move(from: source, to: target)
        save()
    }

    func refresh(key: String) async throws {
        guard let previous = registry.installations.first(where: { $0.key == key }) else {
            throw MusicAddonError.notInstalled
        }
        guard !Self.isSample(previous) else { return }
        let (data, url) = try await MusicAddonManifestDownloader().download(from: previous.manifestURL)
        try registry.update(data: data, from: url)
        save()
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(registry.installations) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
        syncAddonAvailability()
    }

    private func syncAddonAvailability() {
        let hasAddons = installations.contains { $0.isEnabled && $0.manifest.protocolKind == .stremio }
        if SettingsStore.shared.hasMusicAddons != hasAddons {
            SettingsStore.shared.hasMusicAddons = hasAddons
        }
    }

    private func restoreValidatedEntries() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let cached = try? JSONDecoder().decode([MusicAddonInstallation].self, from: data) else { return }
        var restored = MusicAddonRegistry()
        for entry in cached.prefix(MusicAddonRegistry.maxInstalled) {
            let before = restored.installations.count
            restored.restore(entry)
            guard restored.installations.count > before else { continue }
            if entry.isEnabled {
                try? restored.setEnabled(true, for: entry.key)
            }
        }
        registry = restored
    }
}
