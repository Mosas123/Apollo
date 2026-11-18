import Foundation

/// Optional AI plan using the user's configured provider/key. Only metadata is
/// sent (title/artist/BPM/energy/duration), never audio. Invalid output or a
/// missing key falls back to the deterministic planner.
enum DJAIPlanner {
    struct Request: Sendable {
        var instruction: String?
        var targetCrossfade: Double = 3
    }

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
        You are a DJ. Order these tracks for a smooth energy arc and beat-compatible \
        transitions. Reply ONLY with JSON: {"order":[{"id":"...","crossfade":3}],\
        "masterTempo":120}. Use every id exactly once, crossfade between 1 and 6 \
        seconds. \(extra)
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
        for entry in order {
            guard let id = entry["id"] as? String, let pair = byID[id] else { continue }
            let fade = (entry["crossfade"] as? Double) ?? Double(entry["crossfade"] as? Int ?? 3)
            slots.append(DJMixPlan.Slot(
                track: pair.0,
                analysis: pair.1,
                crossfadeSeconds: min(max(fade, 1), 6)
            ))
        }
        guard slots.count == tracks.count else { return nil }
        let master = (root["masterTempo"] as? Double) ?? (root["masterTempo"] as? Int).map(Double.init)
        return DJMixPlan(slots: slots, masterTempo: master)
    }
}
