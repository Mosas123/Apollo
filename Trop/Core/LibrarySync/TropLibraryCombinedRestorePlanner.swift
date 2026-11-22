import Foundation

/// Read-only remapping policy for a future *atomic* combined restore.
///
/// A destination must first prove that the legacy/V2 tables are empty, then
/// insert legacy memberships inside one SQLite transaction and capture their
/// real SQLite-assigned IDs. Never reapply origin-local integer IDs directly.
/// This planner validates that capture and rewrites the V2 legacy-import ledger
/// in memory only; it performs NO database reads or writes.
enum TropLibraryCombinedRestorePlanner {
    enum Blocker: Error, Equatable, Sendable {
        case incompleteMembershipMapping
        case unknownSourceMembership
        case wrongMembershipIdentity
        case duplicateSourceMapping
        case duplicateDestinationID
        case invalidDestinationID
        case orphanedImportTombstone
    }

    /// The exact source membership tuple paired with the ID actually
    /// allocated during insertion into a verified-empty destination DB.
    struct DestinationMembership: Equatable, Sendable {
        let sourceRowID: Int64
        let assignedRowID: Int64
        let playlistID: String
        let songID: String
        let position: Int
    }

    struct Plan: Equatable, Sendable {
        let sourceToDestinationID: [Int64: Int64]
        let remappedImportLedger: [TropLibraryV2RecoverySnapshot.ImportLedger]
        let foreignTombstones: [TropLibraryCombinedBackupSnapshot.ForeignTombstone]
    }

    /// Requires a previously checked, versioned, checksum-valid combined
    /// archive. This fails closed when ledger tombstones refer to memberships
    /// that were already removed from the source legacy database.
    ///
    /// No guessing by order, video ID or playlist position: every source
    /// membership must have exactly one confirmed destination assignment.
    static func prepare(
        archive: Data,
        insertedMemberships: [DestinationMembership]
    ) throws -> Plan {
        let source = try TropLibraryCombinedBackupArchive.decode(archive).library
        return try prepare(source: source, insertedMemberships: insertedMemberships)
    }

    /// Internal entry point for a future single-transaction GRDB importer.
    /// The source must be validated by the combined archive decoder first.
    private static func prepare(
        source: TropLibraryCombinedBackupSnapshot,
        insertedMemberships: [DestinationMembership]
    ) throws -> Plan {
        guard source.legacyMemberships.count == insertedMemberships.count else {
            throw Blocker.incompleteMembershipMapping
        }

        let originByID = Dictionary(
            uniqueKeysWithValues: source.legacyMemberships.map {
                ($0.sourceRowID, $0)
            }
        )
        var assigned = Set<Int64>()
        var mapped: [Int64: Int64] = [:]
        mapped.reserveCapacity(insertedMemberships.count)

        for entry in insertedMemberships {
            guard let origin = originByID[entry.sourceRowID] else {
                throw Blocker.unknownSourceMembership
            }
            guard origin.playlistID == entry.playlistID,
                  origin.songID == entry.songID,
                  origin.position == entry.position else {
                throw Blocker.wrongMembershipIdentity
            }
            guard entry.assignedRowID > 0 else {
                throw Blocker.invalidDestinationID
            }
            guard assigned.insert(entry.assignedRowID).inserted else {
                throw Blocker.duplicateDestinationID
            }
            guard mapped.updateValue(
                entry.assignedRowID, forKey: entry.sourceRowID
            ) == nil else {
                throw Blocker.duplicateSourceMapping
            }
        }
        guard mapped.count == originByID.count else {
            throw Blocker.incompleteMembershipMapping
        }

        var ledger: [TropLibraryV2RecoverySnapshot.ImportLedger] = []
        var foreign = source.foreignTombstones
        var seen = Set(foreign.map {
            $0.originScope + ":" + String($0.sourceMembershipID)
        })
        for row in source.libraryV2.importLedger {
            if let destinationID = mapped[row.legacyMembershipID] {
                ledger.append(.init(
                    legacyMembershipID: destinationID,
                    entryID: row.entryID, importedAt: row.importedAt
                ))
            } else {
                // Orphans remain in their source installation's namespace.
                // Never invent a local integer ID or discard history.
                let key = source.originScope + ":" + String(row.legacyMembershipID)
                guard seen.insert(key).inserted else {
                    throw Blocker.duplicateSourceMapping
                }
                foreign.append(.init(
                    originScope: source.originScope,
                    sourceMembershipID: row.legacyMembershipID,
                    entryID: row.entryID, importedAt: row.importedAt
                ))
            }
        }
        return Plan(
            sourceToDestinationID: mapped,
            remappedImportLedger: ledger, foreignTombstones: foreign
        )
    }
}
