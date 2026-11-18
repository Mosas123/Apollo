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

    /// Re-adds a previously validated installation without re-parsing it
    /// (Stremio manifests don't round-trip through a JSON re-encode).
    mutating func restore(_ installation: MusicAddonInstallation) {
        guard installations.count < Self.maxInstalled,
              !installation.manifest.capabilities.isEmpty,
              !installation.manifest.id.isEmpty,
              !installation.manifest.name.isEmpty,
              !installations.contains(where: { $0.key == installation.key }) else { return }
        installations.append(installation)
    }
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

    /// Reorder only; no provider requests and no capability changes.
    mutating func move(from source: Int, to target: Int) {
        guard installations.indices.contains(source),
              installations.indices.contains(target),
              source != target else { return }
        let entry = installations.remove(at: source)
        installations.insert(entry, at: target)
    }

    mutating func remove(key: String) throws {
        guard let index = installations.firstIndex(where: { $0.key == key }) else {
            throw MusicAddonError.notInstalled
        }
        installations.remove(at: index)
    }
}
