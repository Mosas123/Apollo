import Foundation

/// Deterministic, bounded, resumable scanning over saved Trop-owned UUIDs.
/// The cursor is a recording UUID rather than a provider ID or playback URL.
/// A deleted recording does not invalidate the next batch.
enum TropLibraryV2PrelinkBatchPolicy {
    static let batchSize = 8
    static let cursorKey = "trop.match.libraryV2.batchCursor"

    struct Page: Equatable, Sendable {
        let recordingIDs: [String]
        let completedBefore: Int
        let total: Int
        let hasMore: Bool
    }

    static func page(savedIDs: [String], after rawCursor: String?) -> Page {
        // Even when a caller supplies overlapping playlist memberships,
        // scan each saved recording UUID at most once in a batch.
        let ordered = Array(Set(savedIDs.filter {
            TropLibraryV2IdentityPolicy.isCanonicalID($0)
        })).sorted()
        let cursor = rawCursor.flatMap {
            TropLibraryV2IdentityPolicy.isCanonicalID($0) ? $0 : nil
        }
        let start = cursor.map { cursor in
            ordered.firstIndex(where: { $0 > cursor }) ?? ordered.count
        } ?? 0
        let end = min(ordered.count, start + batchSize)
        let ids = Array(ordered[start..<end])
        return Page(
            recordingIDs: ids, completedBefore: start, total: ordered.count,
            hasMore: end < ordered.count
        )
    }

    static func status(savedIDs: [String], after cursor: String?) -> (
        completed: Int, total: Int
    ) {
        let page = page(savedIDs: savedIDs, after: cursor)
        return (page.completedBefore, page.total)
    }
}
