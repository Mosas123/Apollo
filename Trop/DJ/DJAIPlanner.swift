import Foundation

/// Optional AI plan using the user's configured provider/key. Only metadata is
/// sent (title/artist/BPM/energy/duration), never audio. The AI decides the
/// whole set: order, where each track enters, transition type/duration and
/// effects. Invalid output or a missing key falls back to DJMixPlanner.
enum DJAIPlanner {
    struct Request: Sendable {
        var instruction: String?
        var targetCrossfade: Double = 3
    }

    private static let supportedEffects: Set<String> = [
        "filterSweep", "echo", "reverb", "delay", "loop", "bassSwap",
        "cut", "backspin", "gate", "roll", "reverse", "custom"
    ]

    static func plan(
        tracks: [(DJSourceTrack, DJTrackAnalysis)],
        request: Request
    ) async -> DJMixPlan? {
        guard tracks.count >= 2,
              let client = await AIProviderClient.configured() else { return nil }
        let roster = tracks.map { track, analysis in
            [
                "id": track.id,
                "title": track.title,
                "artist": track.artist,
                "bpm": analysis.bpm ?? 0,
                "energy": analysis.energy,
                "duration": analysis.duration
            ] as [String: Any]
        }
        let payload = (try? JSONSerialization.data(withJSONObject: roster)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "[]"
        let extra = request.instruction.map { "User request: \($0)" } ?? "No extra request."
        let prompt = """
        You are a live DJ planning a WHOLE set. You choose any order, the exact \
        moment each track enters, the transition between tracks and optional \
        effects. Be creative but musical: respect energy arcs, keys and BPM.
        Reply ONLY with JSON:
        {"order":[{"id":"...","cueIn":12.5,"enter":{"type":"crossfade","seconds":4,\
        "effects":[{"name":"filterSweep","amount":0.6,"startSeconds":2,"endSeconds":4}]}}],\
        "masterTempo":122,"notes":"short rationale"}
        Use every id exactly once. cueIn is seconds into the track where it should \
        start (0 for the first). enter describes how it comes in (the first slot may \
        omit it). type is one of: crossfade, cut, filterSweep, echoOut, bassSwap, \
        loopRoll, backspin, custom. seconds between 0.5 and 12. effects are optional, \
        name one of: filterSweep, echo, reverb, delay, loop, bassSwap, cut, backspin, \
        gate, roll, reverse. \(extra)
        Tracks: \(payload)
        """
        guard let reply = try? await client.complete(prompt),
              let start = reply.firstIndex(of: "{"),
              let end = reply.lastIndex(of: "}") else { return nil }
        let json = String(reply[start...end])
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let order = root["order"] as? [[String: Any]] else { return nil }

        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.0.id, $0) })
        var slots: [DJMixPlan.Slot] = []
        var seen = Set<String>()
        for entry in order {
            guard let id = entry["id"] as? String,
                  let pair = byID[id],
                  seen.insert(id).inserted else { continue }
            let enter = entry["enter"] as? [String: Any]
            let legacyFade = double(entry["crossfade"]) ?? request.targetCrossfade
            let seconds = min(max(double(enter?["seconds"]) ?? legacyFade, 0.5), 12)
            let kind = transitionKind(enter?["type"] as? String)
            let effects = parseEffects(enter?["effects"] ?? entry["effects"])
            let cue = clamp(double(entry["cueIn"]), 0, pair.1.duration)
            slots.append(DJMixPlan.Slot(
                track: pair.0,
                analysis: pair.1,
                crossfadeSeconds: slots.isEmpty ? 0 : seconds,
                transition: slots.isEmpty ? nil : DJTransition(kind: kind, seconds: seconds, effects: effects),
                cueInSeconds: cue
            ))
        }
        guard slots.count == tracks.count,
              Set(slots.map(\.track.id)) == Set(tracks.map(\.0.id)) else { return nil }
        let master = clamp(double(root["masterTempo"]), 60, 200)
        let notes = (root["notes"] as? String).map { String($0.prefix(280)) }
        return DJMixPlan(slots: slots, masterTempo: master, notes: notes)
    }

    private static func parseEffects(_ raw: Any?) -> [DJEffect] {
        guard let list = raw as? [Any] else { return [] }
        var effects: [DJEffect] = []
        for item in list.prefix(6) {
            if let name = item as? String, supportedEffects.contains(name) {
                effects.append(DJEffect(name: name, amount: nil, startSeconds: nil, endSeconds: nil))
                continue
            }
            guard let dict = item as? [String: Any],
                  let name = dict["name"] as? String,
                  supportedEffects.contains(name) else { continue }
            effects.append(DJEffect(
                name: name,
                amount: clamp(double(dict["amount"]), 0, 1),
                startSeconds: double(dict["startSeconds"]),
                endSeconds: double(dict["endSeconds"])
            ))
        }
        return effects
    }

    private static func transitionKind(_ raw: String?) -> DJTransitionKind {
        guard let raw, let kind = DJTransitionKind(rawValue: raw) else { return .crossfade }
        return kind
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func clamp(_ value: Double?, _ lower: Double, _ upper: Double) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, lower), upper)
    }
}
