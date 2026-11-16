import Foundation

struct MusicAddonInstallation: Sendable, Codable, Equatable {
    let manifestURL: URL
    var manifest: MusicAddonManifest
    var isEnabled: Bool

    var key: String { "\(manifestURL.absoluteString)#\(manifest.id)" }
}

/// Pure in-memory state machine. In a later PR a settings UI/persistence layer
/// may use it, but an addon can never execute code or make network requests here.
struct MusicAddonRegistry: Sendable {
    private(set) var installations: [MusicAddonInstallation] = []
    static let maxInstalled = 30

    mutating func install(data: Data, from url: URL) throws {
        let package = try MusicAddonPackage.parse(data, from: url)
        guard !installations.contains(where: { $0.key == package.installationKey }) else {
            throw MusicAddonError.alreadyInstalled
        }
        guard installations.count < Self.maxInstalled else { throw MusicAddonError.tooManyAddons }
        installations.append(MusicAddonInstallation(
            manifestURL: package.manifestURL,
            manifest: package.manifest,
            isEnabled: false // require explicit opt-in to remote providers
        ))
    }

    mutating func update(data: Data, from url: URL) throws {
        let candidate = try MusicAddonPackage.parse(data, from: url)
        guard let index = installations.firstIndex(where: { $0.key == candidate.installationKey }) else {
            throw MusicAddonError.notInstalled
        }
        let oldCapabilities = Set(installations[index].manifest.capabilities)
        let newCapabilities = Set(candidate.manifest.capabilities)
        guard newCapabilities.isSubset(of: oldCapabilities) else {
            throw MusicAddonError.requiresCapabilityApproval
        }
        installations[index].manifest = candidate.manifest
    }

    mutating func setEnabled(_ enabled: Bool, for key: String) throws {
        guard let index = installations.firstIndex(where: { $0.key == key }) else {
            throw MusicAddonError.notInstalled
        }
        installations[index].isEnabled = enabled
    }

    mutating func remove(key: String) throws {
        guard let index = installations.firstIndex(where: { $0.key == key }) else {
            throw MusicAddonError.notInstalled
        }
        installations.remove(at: index)
    }
}
