import Foundation

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@main
struct StationIntentMixChecks {
    static func main() {
        let intents: [StationIntent] = [
            .familiar, .familiar, .popular, .discover,
            .deepCuts, .genre, .romance, .party, .genre, .discover
        ]

        var g1 = SeededGenerator(seed: 42)
        var g2 = SeededGenerator(seed: 42)
        let a = StationIntentMix.order(intents: intents, generator: &g1)
        let b = StationIntentMix.order(intents: intents, generator: &g2)
        precondition(a == b, "same seed must be deterministic")
        precondition(a.sorted() == Array(intents.indices), "must be a permutation")
        precondition(Set(a).count == intents.count, "no duplicate indices")

        var g3 = SeededGenerator(seed: 1)
        precondition(StationIntentMix.order(intents: [], generator: &g3).isEmpty)

        let single = [StationIntent](repeating: .genre, count: 4)
        var g4 = SeededGenerator(seed: 7)
        precondition(StationIntentMix.order(intents: single, generator: &g4) == [0, 1, 2, 3])

        var heavy = StationIntentMix.defaultWeights
        heavy[.genre] = 1000
        var g5 = SeededGenerator(seed: 9)
        let weighted = StationIntentMix.order(intents: intents, weights: heavy, generator: &g5)
        precondition(weighted.sorted() == Array(intents.indices), "weighted order is still a permutation")

        print("StationIntentMixChecks passed")
    }
}
