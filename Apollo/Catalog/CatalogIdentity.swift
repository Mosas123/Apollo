import Foundation

/// Identity used to collapse the same recording across providers. ISRC is the
/// strongest key; MBID is next; the fallback is deliberately conservative.
struct CatalogIdentity: Hashable, Sendable {
    let key: String
    let isrc: String?
    let mbid: String?

    static func resolve(track: CatalogTrack, enrichment: CatalogEnrichment = CatalogEnrichment()) -> CatalogIdentity {
        if let isrc = (enrichment.isrc ?? track.isrc)?.uppercased(), !isrc.isEmpty {
            return CatalogIdentity(key: "isrc:\(isrc)", isrc: isrc, mbid: nil)
        }
        if let mbid = enrichment.mbid, !mbid.isEmpty {
            return CatalogIdentity(key: "mbid:\(mbid)", isrc: nil, mbid: mbid)
        }

        let title = TextMatch.normalizeTitle(track.title)
        let artist = track.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""
        let durationBucket = track.durationMS > 0 ? track.durationMS / 2000 : 0
        return CatalogIdentity(
            key: "fallback:\(title)|\(artist)|\(durationBucket)",
            isrc: nil,
            mbid: nil
        )
    }
}

struct CanonicalTrack: Identifiable, Sendable {
    let id: String
    var track: CatalogTrack
    var enrichment: CatalogEnrichment
    var sources: Set<CatalogSource>
}

/// In-memory canonical store. UI/DB persistence will land in a later phase.
actor CatalogMerger {
    static let shared = CatalogMerger()

    private var records: [String: CanonicalTrack] = [:]
    private let maxEntries = 2048

    func merge(_ track: CatalogTrack, enrichment: CatalogEnrichment = CatalogEnrichment()) -> CanonicalTrack {
        let identity = CatalogIdentity.resolve(track: track, enrichment: enrichment)

        if var existing = records[identity.key] {
            existing.sources.insert(track.source)
            existing.enrichment = existing.enrichment.merged(with: enrichment)
            existing.track = existing.track.applying(existing.enrichment)
            records[identity.key] = existing
            return existing
        }

        if records.count >= maxEntries { records.removeAll(keepingCapacity: true) }
        let record = CanonicalTrack(
            id: identity.key,
            track: track.applying(enrichment),
            enrichment: enrichment,
            sources: [track.source]
        )
        records[identity.key] = record
        return record
    }

    func record(for identity: CatalogIdentity) -> CanonicalTrack? {
        records[identity.key]
    }

    func reset() {
        records.removeAll(keepingCapacity: true)
    }
}
