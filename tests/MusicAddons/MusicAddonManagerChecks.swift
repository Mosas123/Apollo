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

        // NullBeat-style Eclipse manifests declare an Atmos toggle with
        // JSON boolean default. This is a public protocol-shaped fixture,
        // not a request to any configured account or private addon endpoint.
        let nullbeatStyle = Data("""
        {
          "id":"com.nullbeat.addon.example","name":"NullBeat-like Music",
          "version":"1.0.2","description":"Synthetic parser regression",
          "resources":["search","stream","settings","catalog","isrc"],
          "types":["track","album","artist","playlist"],
          "settings":[
            {"key":"quality","type":"select","default":"max",
             "options":[{"value":"max","label":"MAX"},{"value":"lossless","label":"CD"}]},
            {"key":"atmos","type":"toggle","default":true},
            {"key":"retries","type":"number","default":3},
            {"key":"ratio","type":"number","default":1.5}
          ],
          "catalogs":[{"type":"track","id":"top_tracks","name":"Top"}]
        }
        """.utf8)
        let nullbeatPackage = try MusicAddonPackage.parse(nullbeatStyle, from: beta)
        precondition(nullbeatPackage.manifest.protocolKind == .stremio)
        precondition(nullbeatPackage.manifest.capabilities.contains(.search))
        precondition(nullbeatPackage.manifest.capabilities.contains(.stream))
        let settings = nullbeatPackage.manifest.stremio?.settings ?? []
        precondition(settings.first(where: { $0.key == "quality" })?.default == "max")
        precondition(settings.first(where: { $0.key == "atmos" })?.default == "true")
        precondition(settings.first(where: { $0.key == "retries" })?.default == "3")
        precondition(settings.first(where: { $0.key == "ratio" })?.default == "1.5")
        let persisted = try JSONEncoder().encode(nullbeatPackage.manifest)
        let restoredStremio = try JSONDecoder().decode(MusicAddonManifest.self, from: persisted)
        precondition(restoredStremio.stremio?.settings == settings)

        let disabledAtmos = Data(
            String(decoding: nullbeatStyle, as: UTF8.self)
                .replacingOccurrences(of: "\"default\":true", with: "\"default\":false")
                .utf8
        )
        let disabledPackage = try MusicAddonPackage.parse(disabledAtmos, from: beta)
        precondition(
            disabledPackage.manifest.stremio?.settings?
                .first(where: { $0.key == "atmos" })?.default == "false"
        )

        // Eclipse addons may offer identity-based /resolve without /search.
        // This fixture intentionally contains NO account or token.
        let resolverOnly = Data("""
        {"id":"org.example.nebula","name":"Nebula-style Resolver",
         "version":"1.0.0","resources":["stream","resolve","isrc"],
         "types":["track"],"contentType":"music"}
        """.utf8)
        let resolverPackage = try MusicAddonPackage.parse(resolverOnly, from: beta)
        precondition(resolverPackage.manifest.protocolKind == .stremio)
        precondition(resolverPackage.manifest.stremio?.usesEclipseRouting == true)
        precondition(resolverPackage.manifest.stremio?.offers("resolve") == true)
        precondition(resolverPackage.manifest.stremio?.offers("search") == false)
        precondition(resolverPackage.manifest.capabilities.contains(.stream))

        // A declared Eclipse /search resource wins even if the manifest also
        // has a traditional searchable catalog, avoiding silent wrong routing.
        let mixed = Data("""
        {"id":"org.example.eclipse","name":"Mixed Eclipse Catalog",
         "version":"1.0.0","resources":["search","stream","catalog"],
         "types":["track"],"contentType":"music",
         "catalogs":[{"id":"top","type":"track",
          "extra":[{"name":"search"}]}]}
        """.utf8)
        let mixedPackage = try MusicAddonPackage.parse(mixed, from: beta)
        precondition(mixedPackage.manifest.stremio?.usesEclipseRouting == true)
        precondition(mixedPackage.manifest.stremio?.offers("search") == true)

        // A standard Stremio addon with only catalog search stays Stremio.
        precondition(stremioPackage.manifest.stremio?.usesEclipseRouting == false)

        // Native Apollo manifests remain installable.
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
