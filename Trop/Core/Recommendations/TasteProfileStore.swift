import Foundation

/// On-device taste profile learned from listening, likes and skips since the
/// first use: artist and genre weights plus skip counts. Persisted locally (no
/// account, nothing uploaded) so the app can suggest songs, artists and
/// podcasts even when the AI is off — Apple Music / Spotify's learn-on-device
/// idea.
@MainActor
final class TasteProfileStore {
    static let shared = TasteProfileStore()

    private struct Snapshot: Codable {
        var artistWeights: [String: Double] = [:]
        var genreWeights: [String: Double] = [:]
        /// Artist -> genre; empty string means "looked up, none found".
        var artistGenres: [String: String] = [:]
        var skipCounts: [String: Int] = [:]
        var lastUpdated: Date = Date()
    }

    private struct ITunesResponse: Decodable {
        struct Result: Decodable { let primaryGenreName: String? }
        let results: [Result]?
    }

    private let storageKey = "tasteProfile.v2"
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

    func recordPlay(artist: String?) {
        add(artist, 1)
        guard let artist = clean(artist) else { return }
        if let genre = snapshot.artistGenres[artist], !genre.isEmpty {
            snapshot.genreWeights[genre, default: 0] += 1
            save()
        } else if snapshot.artistGenres[artist] == nil {
            Task { await learnGenre(artist) }
        }
    }

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

    /// Heaviest genres first, after applying time decay.
    func topGenres(limit: Int) -> [String] {
        decayIfNeeded()
        return snapshot.genreWeights
            .filter { $0.value > 0 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    var isEmpty: Bool { snapshot.artistWeights.isEmpty }

    // MARK: - Genre learning

    private func learnGenre(_ artist: String) async {
        let genre = await fetchGenre(for: artist) ?? ""
        guard snapshot.artistGenres[artist] == nil else { return }
        snapshot.artistGenres[artist] = genre
        if !genre.isEmpty {
            snapshot.genreWeights[genre, default: 0] += 1
        }
        save()
    }

    private func fetchGenre(for artist: String) async -> String? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: artist),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "attribute", value: "artistTerm"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(ITunesResponse.self, from: data),
              let genre = decoded.results?.first?.primaryGenreName else { return nil }
        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Internals

    private func add(_ artist: String?, _ delta: Double) {
        guard let artist = clean(artist) else { return }
        decayIfNeeded()
        let updated = (snapshot.artistWeights[artist] ?? 0) + delta
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
        snapshot.genreWeights = snapshot.genreWeights.mapValues { $0 * factor }
        snapshot.lastUpdated = Date()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
