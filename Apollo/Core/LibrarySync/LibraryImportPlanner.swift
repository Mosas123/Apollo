import Foundation

/// A library identity must be scoped to a provider *and* a signed-in account.
/// Raw YouTube IDs are not globally unique across providers, and two Google
/// accounts must never share ownership or edit state by accident.
struct LibrarySourceReference: Hashable, Codable, Sendable {
    let provider: String
    let accountID: String
    let remoteID: String
}

enum UnifiedLibraryItemKind: String, Codable, Hashable, Sendable, CaseIterable {
    case track
    case album
    case artist
    case playlist
    case podcast
    case episode
}

/// Metadata only. This never represents downloaded audio or a stream URL.
struct IncomingLibraryItem: Sendable, Equatable {
    let kind: UnifiedLibraryItemKind
    let source: LibrarySourceReference
    let title: String
    /// Only a validated ISRC is eligible for cross-provider track matching.
    /// The provider's track ID is still saved as separate provenance.
    let isrc: String?

    init(
        kind: UnifiedLibraryItemKind, source: LibrarySourceReference,
        title: String, isrc: String? = nil
    ) {
        self.kind = kind
        self.source = source
        self.title = title
        self.isrc = isrc
    }
}

/// A persisted catalogue entry may already have edits, likes, progress,
/// playlist membership and several provider references. None of these fields
/// are overwritten by this read-only merge planner.
struct ExistingLibraryItem: Sendable, Equatable {
    let canonicalID: String
    let kind: UnifiedLibraryItemKind
    let sources: [LibrarySourceReference]
    let isrc: String?
}

struct ProposedLibraryInsert: Sendable, Equatable {
    let kind: UnifiedLibraryItemKind
    let title: String
    let isrc: String?
    var sources: [LibrarySourceReference]
}

struct ProposedSourceLink: Sendable, Equatable {
    let canonicalID: String
    let source: LibrarySourceReference
}

struct LibraryImportPreview: Sendable, Equatable {
    var inserts: [ProposedLibraryInsert] = []
    var links: [ProposedSourceLink] = []
    var alreadyPresent: [LibrarySourceReference] = []
    var duplicateInputs: [LibrarySourceReference] = []
    var skippedUnselected: [LibrarySourceReference] = []
    var needsReview: [LibrarySourceReference] = []

    var totalNewLibraryItems: Int { inserts.count }
    var totalNewSourceLinks: Int {
        links.count + inserts.reduce(0) { $0 + $1.sources.count }
    }
}

enum LibraryImportError: Error, Equatable {
    case emptyAccount
    case accountChanged
    case invalidSource
    case tooManyItems
}

/// Pure dry-run planner: **no database writes, network, auth or scrobbling**.
/// Missing remote items are never interpreted as local deletions. User edits,
/// playlist ordering, local playback progress and likes stay untouched.
struct LibraryImportPlanner: Sendable {
    static let maximumBatchSize = 25_000

    func preview(
        incoming: [IncomingLibraryItem],
        existing: [ExistingLibraryItem],
        activeAccountID: String,
        selectedKinds: Set<UnifiedLibraryItemKind>
    ) throws -> LibraryImportPreview {
        guard !activeAccountID.isEmpty else { throw LibraryImportError.emptyAccount }
        guard incoming.count <= Self.maximumBatchSize,
              existing.count <= Self.maximumBatchSize else { throw LibraryImportError.tooManyItems }

        // Fail the entire batch on cross-account data. Do not silently filter
        // it, which could make an incomplete scan look like a legitimate purge.
        for item in incoming {
            guard item.source.accountID == activeAccountID else {
                throw LibraryImportError.accountChanged
            }
            guard isValid(item.source), !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibraryImportError.invalidSource
            }
        }

        var bySource: [LibrarySourceReference: [ExistingLibraryItem]] = [:]
        var byISRC: [String: Set<String>] = [:]
        for entry in existing {
            for source in entry.sources {
                bySource[source, default: []].append(entry)
            }
            if entry.kind == .track, let isrc = Self.normalizedISRC(entry.isrc) {
                byISRC[isrc, default: []].insert(entry.canonicalID)
            }
        }

        var preview = LibraryImportPreview()
        var seenSources = Set<LibrarySourceReference>()
        var pendingTrackInsert: [String: Int] = [:]

        for item in incoming {
            guard selectedKinds.contains(item.kind) else {
                preview.skippedUnselected.append(item.source)
                continue
            }
            guard seenSources.insert(item.source).inserted else {
                preview.duplicateInputs.append(item.source)
                continue
            }

            let sourceMatches = bySource[item.source] ?? []
            if sourceMatches.count > 1 || sourceMatches.first.map({ $0.kind != item.kind }) == true {
                preview.needsReview.append(item.source)
                continue
            }
            if sourceMatches.count == 1 {
                preview.alreadyPresent.append(item.source)
                continue
            }

            // Never merge artists, albums, podcasts, episodes or playlists
            // by their names. Different editions and playlists can have
            // identical names. This intentionally prefers safe duplicates
            // to a false positive that corrupts a user's library.
            let verifiedISRC = item.kind == .track ? Self.normalizedISRC(item.isrc) : nil
            if let verifiedISRC {
                let matches = byISRC[verifiedISRC] ?? []
                if matches.count > 1 {
                    preview.needsReview.append(item.source)
                    continue
                }
                if let canonicalID = matches.first {
                    preview.links.append(ProposedSourceLink(
                        canonicalID: canonicalID, source: item.source
                    ))
                    continue
                }
                if let index = pendingTrackInsert[verifiedISRC] {
                    preview.inserts[index].sources.append(item.source)
                    continue
                }
            }

            if let verifiedISRC {
                pendingTrackInsert[verifiedISRC] = preview.inserts.count
            }
            preview.inserts.append(ProposedLibraryInsert(
                kind: item.kind, title: item.title, isrc: verifiedISRC,
                sources: [item.source]
            ))
        }
        return preview
    }

    private func isValid(_ reference: LibrarySourceReference) -> Bool {
        !reference.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !reference.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !reference.remoteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        reference.provider.count <= 80 &&
        reference.accountID.count <= 160 &&
        reference.remoteID.count <= 512
    }

    static func normalizedISRC(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.uppercased().filter { $0 != "-" && $0 != " " }
        guard value.utf8.count == 12,
              value.utf8.allSatisfy({
                  (65...90).contains($0) || (48...57).contains($0)
              }),
              value.prefix(2).utf8.allSatisfy({ (65...90).contains($0) }),
              value.suffix(7).utf8.allSatisfy({ (48...57).contains($0) })
        else { return nil }
        return value
    }
}
