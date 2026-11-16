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
