import Foundation

@main
struct MusicAddonManagerChecks {
    static func main() throws {
        let alpha = URL(string: "https://addons.example.org/a/manifest.json")!
        let beta = URL(string: "https://another.example.org/b/manifest.json")!
        let first = Data("""
        {"schemaVersion":1,"id":"radio.music","name":"Radio One",
         "version":"1.0.0","capabilities":["search","stream"],
         "endpoints":{"search":"/api/search","stream":"/api/play"}}
        """.utf8)
        let second = Data("""
        {"schemaVersion":1,"id":"radio.music","name":"Radio Two",
         "version":"2.0.0","capabilities":["lyrics"],
         "endpoints":{"lyrics":"/api/lyrics"}}
        """.utf8)
        precondition(MusicAddonPackage.validatedManifestURL(alpha) == alpha)
        precondition(MusicAddonPackage.validatedManifestURL(URL(string: "http://addons.example.org/manifest.json")!) == nil)
        precondition(MusicAddonPackage.validatedManifestURL(URL(string: "https://localhost/manifest.json")!) == nil)

        // Stremio music catalogs are supported as declarative addons.
        // Verify protocol classification, permissions and disabled-by-default
        // installation rather than expecting the removed incompatibility error.
        let stremio = Data("""
        {"id":"community.lastfm.telegram","name":"Flix-Music","version":"1.0.0",
         "resources":["catalog","meta","stream"],"types":["movie"],
         "catalogs":[{"type":"movie","id":"lastfm-top","name":"Music - Top"}]}
        """.utf8)
        let stremioPackage = try MusicAddonPackage.parse(stremio, from: alpha)
        precondition(stremioPackage.manifest.protocolKind == .stremio)
        precondition(Set(stremioPackage.manifest.capabilities) == Set([.search, .stream, .metadata]))
        precondition(stremioPackage.manifest.stremio?.catalogs.first?.id == "lastfm-top")
        var stremioRegistry = MusicAddonRegistry()
        try stremioRegistry.install(data: stremio, from: alpha)
        precondition(stremioRegistry.installations.count == 1)
        precondition(stremioRegistry.installations[0].manifest.protocolKind == .stremio)
        precondition(!stremioRegistry.installations[0].isEnabled)

        // Native Trop manifests remain installable.
        var registry = MusicAddonRegistry()
        try registry.install(data: first, from: alpha)
        try registry.install(data: second, from: beta)
        precondition(registry.installations.count == 2)
        precondition(registry.installations.allSatisfy { !$0.isEnabled })
        precondition(registry.installations[0].key != registry.installations[1].key)

        let firstKey = registry.installations[0].key
        try registry.setEnabled(true, for: firstKey)
        precondition(registry.installations[0].isEnabled)
        registry.move(from: 0, to: 1)
        precondition(registry.installations[1].key == firstKey)
        registry.move(from: -1, to: 0)
        registry.move(from: 1, to: 4)
        precondition(registry.installations[1].key == firstKey)

        let updatedFirst = Data("""
        {"schemaVersion":1,"id":"radio.music","name":"Radio One",
         "version":"1.1.0","capabilities":["stream"],
         "endpoints":{"stream":"/api/play"}}
        """.utf8)
        try registry.update(data: updatedFirst, from: alpha)
        precondition(registry.installations[1].manifest.version == "1.1.0")
        precondition(registry.installations[1].isEnabled)

        let expanded = Data("""
        {"schemaVersion":1,"id":"radio.music","name":"Radio One",
         "version":"2.0.0","capabilities":["search","stream","history"],
         "endpoints":{"search":"/api/search","stream":"/api/play","history":"/api/history"}}
        """.utf8)
        do {
            try registry.update(data: expanded, from: alpha)
            preconditionFailure("Expanded permissions should require re-approval")
        } catch MusicAddonError.requiresCapabilityApproval {}

        let encoded = try JSONEncoder().encode(registry.installations)
        let restored = try JSONDecoder().decode([MusicAddonInstallation].self, from: encoded)
        precondition(restored.count == 2)
        precondition(restored[1].isEnabled)
        precondition(restored[1].manifest.version == "1.1.0")
        try registry.remove(key: firstKey)
        precondition(registry.installations.count == 1)
        precondition(registry.installations[0].manifest.name == "Radio Two")
        print("Music addon manager registry checks passed")
    }
}
