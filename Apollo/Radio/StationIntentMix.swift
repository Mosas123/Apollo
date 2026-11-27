import Foundation

/// The intent a station candidate serves. The final queue mixes these at
/// random (no fixed order), weighted by how much each flavour should appear.
enum StationIntent: String, Sendable, CaseIterable {
    case familiar
    case popular
    case discover
    case deepCuts
    case genre
    case romance
    case party
}

/// Pure weighted shuffle over intent buckets. Each bucket keeps its own
/// ranked order; the mixer only decides which bucket to draw from next, so a
/// salsa station still serves salsa but never plays a fixed pattern.
enum StationIntentMix {
    static let defaultWeights: [StationIntent: Double] = [
        .genre: 1.5,
        .familiar: 1.0,
        .popular: 1.0,
        .discover: 0.9,
        .deepCuts: 0.8,
        .romance: 0.6,
        .party: 0.6
    ]

    /// Returns a permutation of the input indices. Deterministic for the same
    /// generator seed; weighted so stronger intents appear more often.
    static func order<G: RandomNumberGenerator>(
        intents: [StationIntent],
        weights: [StationIntent: Double] = defaultWeights,
        generator: inout G
    ) -> [Int] {
        var buckets: [StationIntent: [Int]] = [:]
        for (index, intent) in intents.enumerated() {
            buckets[intent, default: []].append(index)
        }

        var result: [Int] = []
        result.reserveCapacity(intents.count)

        while true {
            var active: [StationIntent] = []
            var total = 0.0
            for intent in StationIntent.allCases {
                if let indices = buckets[intent], !indices.isEmpty {
                    active.append(intent)
                    total += max(0.1, weights[intent] ?? 1.0)
                }
            }
            guard !active.isEmpty else { break }

            var roll = Double.random(in: 0..<total, using: &generator)
            var chosen = active[0]
            for intent in active {
                let weight = max(0.1, weights[intent] ?? 1.0)
                if roll < weight {
                    chosen = intent
                    break
                }
                roll -= weight
            }

            guard var indices = buckets[chosen], !indices.isEmpty else { break }
            result.append(indices.removeFirst())
            buckets[chosen] = indices.isEmpty ? nil : indices
        }
        return result
    }
}
