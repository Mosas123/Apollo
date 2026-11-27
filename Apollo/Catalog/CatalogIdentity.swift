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

    func merge(_ track: CatalogTrack, enrichment: CatalogEnrichment = CatalogEnrichment()) async -> CanonicalTrack {
        let identity = CatalogIdentity.resolve(track: track, enrichment: enrichment)

        var effectiveEnrichment = enrichment
        var storedSources: Set<CatalogSource> = []
        if let stored = try? await DatabaseService.shared.fetchOne(
            CatalogIdentityEntity.self,
            key: identity.key
        ) {
            effectiveEnrichment = stored.enrichment.merged(with: enrichment)
            if let source = CatalogSource(rawValue: stored.source) {
                storedSources.insert(source)
            }
        }

        let record: CanonicalTrack
        if var existing = records[identity.key] {
            existing.sources.formUnion(storedSources)
            existing.sources.insert(track.source)
            existing.enrichment = existing.enrichment.merged(with: effectiveEnrichment)
            existing.track = existing.track.applying(existing.enrichment)
            record = existing
            records[identity.key] = existing
        } else {
            if records.count >= maxEntries { records.removeAll(keepingCapacity: true) }
            record = CanonicalTrack(
                id: identity.key,
                track: track.applying(effectiveEnrichment),
                enrichment: effectiveEnrichment,
                sources: storedSources.union([track.source])
            )
            records[identity.key] = record
        }

        try? await DatabaseService.shared.save(entity(from: record))
        return record
    }

    private func entity(from record: CanonicalTrack) -> CatalogIdentityEntity {
        CatalogIdentityEntity(
            id: record.id,
            source: record.track.source.rawValue,
            title: record.track.title,
            artistNames: record.track.artists.map(\.name).joined(separator: "\n"),
            albumTitle: record.track.album?.title,
            durationMS: record.track.durationMS,
            isrc: record.track.isrc,
            mbid: record.enrichment.mbid,
            artworkURL: record.track.artworkURL?.absoluteString,
            genre: record.enrichment.genre,
            releaseDate: record.enrichment.releaseDate,
            spotifyID: record.track.source == .spotify ? record.track.id : nil,
            youtubeID: record.track.source == .youtube ? record.track.id : nil,
            updatedAt: Date()
        )
    }

    func record(for identity: CatalogIdentity) -> CanonicalTrack? {
        records[identity.key]
    }

    func reset() {
        records.removeAll(keepingCapacity: true)
    }
}
