import Foundation

/// The only persistence entrypoint for Qobuz credentials. Never use
/// UserDefaults, source literals, shared token pools, or diagnostic logs.
actor QobuzCredentialStore {
    static let shared = QobuzCredentialStore()

    private static let key = "qobuz.authorized-credentials.v1"
    private let keychain = KeychainStorage()

    func load() async throws -> QobuzCredentials? {
        do {
            let value: QobuzCredentials = try await keychain.load(for: Self.key)
            return value.isComplete ? value : nil
        } catch KeychainError.itemNotFound {
            return nil
        }
    }

    func isConfigured() async -> Bool {
        (try? await load()) != nil
    }

    func save(_ credentials: QobuzCredentials) async throws {
        guard credentials.isComplete else { throw QobuzError.notConfigured }
        try keychain.save(credentials, for: Self.key)
    }

    func remove() async throws {
        do {
            try keychain.delete(for: Self.key)
        } catch KeychainError.itemNotFound {
            // Removing an already absent account is idempotent.
        }
    }
}

actor QobuzCatalogService {
    static let shared = QobuzCatalogService()

    func searchIfConfigured(query: String, limit: Int = 25) async -> [MusicCatalogTrack] {
        guard let credentials = try? await QobuzCredentialStore.shared.load() else { return [] }
        return (try? await QobuzClient().searchTracks(
            query: query, limit: limit, credentials: credentials
        )) ?? []
    }
}
