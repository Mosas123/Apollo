import Foundation

struct RadioFeatureVector: Codable, Sendable {
    /// [bias, affinity, profile, popularity, novelty, embedding,
    ///  seedTop, album, related, search, skipPressure]
    let values: [Double]
}

struct RadioWeights: Codable, Sendable {
    var bias: Double
    var affinity: Double
    var profile: Double
    var popularity: Double
    var novelty: Double
    var embedding: Double
    var seedTop: Double
    var album: Double
    var related: Double
    var search: Double
    var skipPenalty: Double

    func score(_ features: RadioFeatureVector) -> Double {
        guard features.values.count == 11 else { return 0 }
        let weights = [
            bias, affinity, profile, popularity, novelty, embedding,
            seedTop, album, related, search, skipPenalty
        ]
        return zip(weights, features.values).reduce(0) { $0 + $1.0 * $1.1 }
    }

    mutating func learn(_ features: RadioFeatureVector, label: Double, learningRate: Double = 0.08) {
        guard features.values.count == 11 else { return }
        let predicted = 1 / (1 + exp(-score(features)))
        let gradient = predicted - label
        let keys: [WritableKeyPath<RadioWeights, Double>] = [
            \RadioWeights.bias, \.affinity, \.profile, \.popularity, \.novelty,
            \.embedding, \.seedTop, \.album, \.related, \.search, \.skipPenalty
        ]
        for (index, keyPath) in keys.enumerated() {
            let next = self[keyPath: keyPath] - learningRate * gradient * features.values[index]
            self[keyPath: keyPath] = min(max(next, -4), 4)
        }
    }

    static func initial(for style: String) -> RadioWeights {
        switch style {
        case "variety":
            return RadioWeights(
                bias: 0, affinity: 0.38, profile: 0.20, popularity: 0.10,
                novelty: 0.12, embedding: 0.18, seedTop: 0.85, album: 0.45,
                related: 0.78, search: 0.40, skipPenalty: -0.06
            )
        case "deepCuts":
            return RadioWeights(
                bias: 0, affinity: 0.30, profile: 0.20, popularity: 0.06,
                novelty: 0.10, embedding: 0.15, seedTop: 0.90, album: 1.00,
                related: 0.86, search: 0.40, skipPenalty: -0.06
            )
        default:
            return RadioWeights(
                bias: 0, affinity: 0.30, profile: 0.20, popularity: 0.12,
                novelty: 0.04, embedding: 0.15, seedTop: 1.00, album: 0.90,
                related: 0.80, search: 0.40, skipPenalty: -0.04
            )
        }
    }
}

/// Tiny on-device learning-to-rank: station scores start from hand weights and
/// move with real completions/skips. Weights are per radio style and persisted
/// locally; feature snapshots are ephemeral to the current queue.
actor RadioLearningStore {
    static let shared = RadioLearningStore()

    private struct Snapshot {
        let style: String
        let source: String
        let features: [Double]
        let at: Date
    }

    private let weightsKey = "apollo.radio.weights.v1"
    private var weights: [String: RadioWeights]?
    private var snapshots: [String: Snapshot] = [:]

    func weights(for style: String) -> RadioWeights {
        let all = loadWeights()
        return all[style] ?? .initial(for: style)
    }

    func snapshot(key: String, style: String, source: String, features: RadioFeatureVector) {
        if snapshots.count > 500 { snapshots.removeAll(keepingCapacity: true) }
        snapshots[key] = Snapshot(style: style, source: source, features: features.values, at: Date())
    }

    func record(key: String, label: Double) async {
        guard let snapshot = snapshots[key] else { return }
        snapshots[key] = nil

        var all = loadWeights()
        var current = all[snapshot.style] ?? .initial(for: snapshot.style)
        current.learn(RadioFeatureVector(values: snapshot.features), label: label)
        all[snapshot.style] = current
        weights = all
        saveWeights(all)

        await RadioBanditStore.shared.update(
            style: snapshot.style,
            source: snapshot.source,
            reward: label
        )
    }

    func clear() async {
        weights = [:]
        snapshots.removeAll(keepingCapacity: true)
        UserDefaults.standard.removeObject(forKey: weightsKey)
        await RadioBanditStore.shared.reset()
    }

    private func loadWeights() -> [String: RadioWeights] {
        if let weights { return weights }
        guard let data = UserDefaults.standard.data(forKey: weightsKey),
              let decoded = try? JSONDecoder().decode([String: RadioWeights].self, from: data) else {
            weights = [:]
            return [:]
        }
        weights = decoded
        return decoded
    }

    private func saveWeights(_ value: [String: RadioWeights]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: weightsKey)
    }
}
