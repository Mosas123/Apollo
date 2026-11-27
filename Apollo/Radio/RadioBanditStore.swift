import Foundation

/// Tiny Beta bandit over radio sources. It explores without fighting the
/// hand weights too much: the multiplier stays in a narrow 0.85…1.15 band.
actor RadioBanditStore {
    static let shared = RadioBanditStore()

    private struct Stat: Codable {
        var alpha: Double = 1
        var beta: Double = 1
    }

    private let key = "apollo.radio.bandit.v1"
    private var stats: [String: Stat]?

    func multiplier(style: String, source: String) -> Double {
        let stat = load()["\(style)|\(source)"] ?? Stat()
        let mean = stat.alpha / max(stat.alpha + stat.beta, 0.001)
        return 0.85 + 0.30 * mean
    }

    func update(style: String, source: String, reward: Double) {
        var all = load()
        let id = "\(style)|\(source)"
        var stat = all[id] ?? Stat()
        stat.alpha += max(0, min(1, reward))
        stat.beta += 1 - max(0, min(1, reward))
        all[id] = stat
        stats = all
        save(all)
    }

    func reset() {
        stats = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func load() -> [String: Stat] {
        if let stats { return stats }
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Stat].self, from: data) else {
            stats = [:]
            return [:]
        }
        stats = decoded
        return decoded
    }

    private func save(_ value: [String: Stat]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
