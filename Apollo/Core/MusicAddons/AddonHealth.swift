import Foundation

/// Per-addon health kept for the session: how often each addon answers, how
/// fast, and whether it is parked after repeated failures. The resolver uses it
/// to try fast, reliable addons first and to stop hammering dead ones.
actor AddonHealth {
    static let shared = AddonHealth()

    private struct Stats {
        var successes = 0
        var failures = 0
        var latencies: Double = 2
        var coolingUntil: Date?
    }

    private var stats: [String: Stats] = [:]

    func isCoolingDown(_ key: String) -> Bool {
        guard let until = stats[key]?.coolingUntil else { return false }
        if until > Date() { return true }
        stats[key]?.coolingUntil = nil
        return false
    }

    func score(_ key: String) -> Double {
        guard let entry = stats[key] else { return 0 }
        if let until = entry.coolingUntil, until > Date() { return -1_000 }
        return Double(entry.successes) - 2 * Double(entry.failures) - min(entry.latencies, 8) * 0.25
    }

    /// Best first, cooling addons last.
    func ordered(_ keys: [String]) -> [String] {
        keys.sorted { score($0) > score($1) }
    }

    func recordSuccess(_ key: String, latency: Double) {
        var entry = stats[key] ?? Stats()
        entry.successes += 1
        entry.latencies = entry.latencies * 0.7 + max(0, latency) * 0.3
        entry.coolingUntil = nil
        stats[key] = entry
    }

    /// Answered but had nothing for this track: good enough, not a failure.
    func recordMiss(_ key: String, latency: Double) {
        var entry = stats[key] ?? Stats()
        entry.latencies = entry.latencies * 0.7 + max(0, latency) * 0.3
        stats[key] = entry
    }

    /// Stream/download failed (dead node, 503, truncation): park it.
    func recordFailure(_ key: String, cooldown: TimeInterval = 120) {
        var entry = stats[key] ?? Stats()
        entry.failures += 1
        entry.coolingUntil = Date().addingTimeInterval(cooldown)
        stats[key] = entry
    }
}
