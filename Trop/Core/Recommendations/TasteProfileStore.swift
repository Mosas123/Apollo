import Foundation

/// On-device taste profile learned from listening, likes and skips since the
/// first use. Persisted locally (no account, nothing uploaded) so the app can
/// suggest songs, artists and podcasts even when the AI is off — the same idea
/// as Apple Music / Spotify's "listen and learn" seed.
@MainActor
final class TasteProfileStore {
    static let shared = TasteProfileStore()

    private struct Snapshot: Codable {
        var artistWeights: [String: Double] = [:]
        var skipCounts: [String: Int] = [:]
        var lastUpdated: Date = Date()
    }

    private let storageKey = "tasteProfile.v1"
    private let defaults = UserDefaults.standard
    private var snapshot: Snapshot

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = Snapshot()
        }
    }

    // MARK: - Signals

    func recordPlay(artist: String?) { add(artist, 1) }
    func recordCompletion(artist: String?) { add(artist, 2) }
    func recordLike(artist: String?) { add(artist, 3) }
    func recordUnlike(artist: String?) { add(artist, -3) }

    func recordSkip(artist: String?) {
        guard let artist = clean(artist) else { return }
        decayIfNeeded()
        snapshot.skipCounts[artist, default: 0] += 1
        add(artist, -1)
    }

    // MARK: - Reading

    /// Heaviest artists first, after applying time decay.
    func topArtists(limit: Int) -> [String] {
        decayIfNeeded()
        return snapshot.artistWeights
            .filter { $0.value > 0 && !isSkipped($0.key) }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    var isEmpty: Bool { snapshot.artistWeights.isEmpty }

    // MARK: - Internals

    private func add(_ artist: String?, _ delta: Double) {
        guard let artist = clean(artist) else { return }
        decayIfNeeded()
        let current = snapshot.artistWeights[artist] ?? 0
        let updated = current + delta
        if updated <= 0 {
            snapshot.artistWeights.removeValue(forKey: artist)
        } else {
            snapshot.artistWeights[artist] = updated
        }
        snapshot.lastUpdated = Date()
        save()
    }

    private func clean(_ artist: String?) -> String? {
        let value = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func isSkipped(_ artist: String) -> Bool {
        (snapshot.skipCounts[artist] ?? 0) >= 5
    }

    /// Slowly forgets old taste so the profile follows changes over time.
    private func decayIfNeeded() {
        let days = Date().timeIntervalSince(snapshot.lastUpdated) / 86_400
        guard days >= 1 else { return }
        let factor = pow(0.97, days)
        snapshot.artistWeights = snapshot.artistWeights.mapValues { $0 * factor }
        snapshot.lastUpdated = Date()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
