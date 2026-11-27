import Foundation
import NaturalLanguage

/// On-device metadata embeddings. No audio, no network and no user text leaves
/// the phone; used only as a similarity feature for stations.
actor CatalogEmbeddingStore {
    static let shared = CatalogEmbeddingStore()

    private let embedding: NLEmbedding?
    private var cache: [String: [Float]] = [:]
    private let maxEntries = 2000

    private init() {
        embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    func vector(for text: String) -> [Float]? {
        let key = Self.normalizedText(text)
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        guard let embedding, let raw = embedding.vector(for: key) else { return nil }

        var values = raw.map(Float.init)
        let norm = sqrt(values.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        values = values.map { $0 / norm }

        if cache.count >= maxEntries { cache.removeAll(keepingCapacity: true) }
        cache[key] = values
        return values
    }

    func similarity(_ a: String, _ b: String) -> Double? {
        guard let first = vector(for: a), let second = vector(for: b) else { return nil }
        return Self.cosine(first, second)
    }

    func similarity(_ vector: [Float]?, to text: String) -> Double? {
        guard let vector, let other = self.vector(for: text) else { return nil }
        return Self.cosine(vector, other)
    }

    static func text(for song: SongItem) -> String {
        var parts = [song.title]
        parts.append(contentsOf: song.artists.map(\.name))
        if let album = song.album, !album.isEmpty { parts.append(album) }
        return parts.joined(separator: " ")
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cosine(_ a: [Float], _ b: [Float]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot: Float = 0
        for index in a.indices { dot += a[index] * b[index] }
        return Double(max(-1, min(1, dot)))
    }
}
