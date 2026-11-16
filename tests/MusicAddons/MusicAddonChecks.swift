import Foundation

@main
struct MusicAddonChecks {
    static func main() throws {
        let url = URL(string: "https://ADDONS.DEMO.ORG/radio/manifest.json")!
        let json = """
        {"schemaVersion":1,"id":"demo.radio","name":"Demo Radio",
         "version":"1.2.3","description":"Example manifest, not a real addon",
         "capabilities":["search","lyrics"],
         "endpoints":{"search":"/api/search","lyrics":"/api/lyrics"}}
        """
        let bytes = Data(json.utf8)
        let pkg = try MusicAddonPackage.parse(bytes, from: url)
        precondition(pkg.manifestURL.absoluteString == "https://addons.demo.org/radio/manifest.json")
        precondition(pkg.endpointURL(for: .search)?.absoluteString == "https://addons.demo.org/api/search")
        precondition(pkg.endpointURL(for: .lyrics)?.absoluteString == "https://addons.demo.org/api/lyrics")
        precondition(pkg.endpointURL(for: .stream) == nil)
        precondition(pkg.installationKey == "https://addons.demo.org/radio/manifest.json#demo.radio")

        func fails(_ error: MusicAddonError, _ value: String, url: URL = url) {
            do {
                _ = try MusicAddonPackage.parse(Data(value.utf8), from: url)
                preconditionFailure("Expected rejection: \(error)")
            } catch let found as MusicAddonError {
                precondition(found == error, "Expected \(error), received \(found)")
            } catch {
                preconditionFailure("Unexpected error \(error)")
            }
        }
        for unsafeURL in [
            "http://addons.demo.org/manifest.json",
            "https://example.com@127.0.0.1/manifest.json",
            "https://localhost/manifest.json",
            "https://127.0.0.1/manifest.json",
            "https://10.0.0.3/manifest.json",
            "https://addons.demo.org:8443/manifest.json",
            "https://addons.demo.org/manifest.json?token=secret",
            "https://addons.demo.org/%2e%2e/manifest.json",
            "https://addons.demo.org/other.json",
            "https://addons.local/manifest.json"
        ] {
            fails(.insecureManifestURL, json, url: URL(string: unsafeURL)!)
        }
        fails(.unsupportedSchema, json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"))
        fails(.invalidIdentity, json.replacingOccurrences(of: "demo.radio", with: "../escape"))
        fails(.invalidIdentity, json.replacingOccurrences(of: "1.2.3", with: "1.2"))
        fails(.invalidCapabilities, json.replacingOccurrences(of: "[\"search\",\"lyrics\"]", with: "[\"search\",\"search\"]"))
        fails(.invalidCapabilities, json.replacingOccurrences(of: "[\"search\",\"lyrics\"]", with: "[\"search\"]"))
        for unsafe in ["https://attacker.org/streams", "//attacker.org/streams", "/v1/../admin", "/api/%2e%2e", "/api/search?token=1"] {
            fails(.unsafeEndpoint, json.replacingOccurrences(of: "/api/search", with: unsafe))
        }
        fails(.invalidManifest, String(repeating: " ", count: 65_537))
        var registry = MusicAddonRegistry()
        try registry.install(data: bytes, from: url)
        precondition(registry.installations.count == 1)
        precondition(!registry.installations[0].isEnabled)
        do {
            try registry.install(data: bytes, from: url)
            preconditionFailure("duplicate")
        } catch MusicAddonError.alreadyInstalled {}
        let key = registry.installations[0].key
        try registry.setEnabled(true, for: key)
        precondition(registry.installations[0].isEnabled)
        let changedVersion = Data(json.replacingOccurrences(of: "1.2.3", with: "1.2.4").utf8)
        try registry.update(data: changedVersion, from: url)
        precondition(registry.installations[0].manifest.version == "1.2.4")
        precondition(registry.installations[0].isEnabled)
        let escalated = Data(json
            .replacingOccurrences(of: "[\"search\",\"lyrics\"]", with: "[\"search\",\"lyrics\",\"stream\"]")
            .replacingOccurrences(of: "\"lyrics\":\"/api/lyrics\"", with: "\"lyrics\":\"/api/lyrics\",\"stream\":\"/api/stream\"")
            .utf8)
        do {
            try registry.update(data: escalated, from: url)
            preconditionFailure("capability escalation")
        } catch MusicAddonError.requiresCapabilityApproval {}
        precondition(registry.installations[0].manifest.version == "1.2.4")
        try registry.remove(key: key)
        precondition(registry.installations.isEmpty)
        do {
            try registry.remove(key: key)
            preconditionFailure("missing")
        } catch MusicAddonError.notInstalled {}
        print("Music addon manifest and registry checks passed")
    }
}
