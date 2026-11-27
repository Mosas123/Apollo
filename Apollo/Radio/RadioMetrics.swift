import Foundation

struct RadioStationMetric: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let seedTitle: String
    let style: String
    let candidateCount: Int
    let selectedCount: Int
    let uniqueArtists: Int
    let uniqueAlbums: Int
    let maxArtistRepeat: Int
    let sourceMix: [String: Int]
    let latencyMS: Int
}

actor RadioMetricsStore {
    static let shared = RadioMetricsStore()

    private let key = "apollo.radio.metrics.v1"
    private let maxEntries = 50
    private var entries: [RadioStationMetric]?

    func record(_ metric: RadioStationMetric) {
        var all = load()
        all.insert(metric, at: 0)
        if all.count > maxEntries { all = Array(all.prefix(maxEntries)) }
        entries = all
        save(all)
    }

    func recent(limit: Int = 20) -> [RadioStationMetric] {
        Array(load().prefix(max(1, limit)))
    }

    func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func load() -> [RadioStationMetric] {
        if let entries { return entries }
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RadioStationMetric].self, from: data) else {
            entries = []
            return []
        }
        entries = decoded
        return decoded
    }

    private func save(_ metrics: [RadioStationMetric]) {
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
