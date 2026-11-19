import Foundation

/// A local file the DJ engine can read and mix (never a DRM/remote stream).
struct DJSourceTrack: Sendable, Equatable {
    let id: String
    let title: String
    let artist: String
    let fileURL: URL
    let duration: TimeInterval
}

/// Musical facts extracted from a local file.
struct DJTrackAnalysis: Sendable, Equatable {
    let trackID: String
    let bpm: Double?
    let energy: Double        // 0…1 RMS-based
    let duration: TimeInterval
}

enum DJTransitionKind: String, Codable, Sendable, CaseIterable {
    case crossfade
    case cut
    case filterSweep
    case echoOut
    case bassSwap
    case loopRoll
    case backspin
    case custom
}

/// One effect the AI wants during a transition. The live engine will apply the
/// ones it supports; the offline renderer currently only honours the fade.
struct DJEffect: Codable, Sendable, Equatable {
    let name: String
    let amount: Double?
    let startSeconds: Double?
    let endSeconds: Double?
}

/// How a slot enters: the AI decides between which tracks it mixes and with
/// which effects. `seconds` is also the crossfade length for the renderer.
struct DJTransition: Codable, Sendable, Equatable {
    let kind: DJTransitionKind
    let seconds: Double
    let effects: [DJEffect]
}

struct DJMixPlan: Sendable, Equatable {
    struct Slot: Sendable, Equatable {
        let track: DJSourceTrack
        let analysis: DJTrackAnalysis
        /// Crossfade length into the next slot, in seconds.
        let crossfadeSeconds: Double
        var transition: DJTransition? = nil
        var cueInSeconds: Double? = nil
    }
    let slots: [Slot]
    let masterTempo: Double?
    var notes: String? = nil
}

enum DJMixPlanner {
    /// Orders tracks by energy while keeping tempo changes within a small window.
    /// Deterministic and LLM-free; an AI plan can reorder before rendering.
    static func plan(
        tracks: [(DJSourceTrack, DJTrackAnalysis)],
        targetCrossfade: Double = 3
    ) -> DJMixPlan {
        let usable = tracks.filter { $0.0.duration > 20 }
        guard !usable.isEmpty else { return DJMixPlan(slots: [], masterTempo: nil) }

        let ordered = usable.sorted { lhs, rhs in
            if abs(lhs.1.energy - rhs.1.energy) > 0.08 {
                return lhs.1.energy < rhs.1.energy
            }
            return (lhs.1.bpm ?? 0) < (rhs.1.bpm ?? 0)
        }
        let bpms = ordered.compactMap(\.1.bpm).filter { $0 > 40 }
        let master = bpms.isEmpty ? nil : bpms.reduce(0, +) / Double(bpms.count)

        let slots = ordered.enumerated().map { index, pair in
            let isLast = index == ordered.count - 1
            let jump = abs((pair.1.bpm ?? master ?? 0) - (master ?? 0))
            let fade = isLast ? 0 : min(max(targetCrossfade, 1), jump > 6 ? 2 : targetCrossfade)
            return DJMixPlan.Slot(
                track: pair.0,
                analysis: pair.1,
                crossfadeSeconds: fade,
                transition: isLast ? nil : DJTransition(kind: .crossfade, seconds: fade, effects: [])
            )
        }
        return DJMixPlan(slots: slots, masterTempo: master)
    }
}
