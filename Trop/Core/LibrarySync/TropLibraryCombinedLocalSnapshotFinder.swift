import Foundation

/// Picker-independent verification of an exported combined metadata archive
/// inside this app's own Documents directory. No database writes, no iCloud
/// traversal, no external File Provider access and no arbitrary file paths.
enum TropLibraryCombinedLocalSnapshotFinder {
    enum LookupError: Error {
        case noSnapshot
        case invalidFile
        case oversized
    }

    static let filenamePrefix = "Trop-Combined-Experimental-Snapshot"

    struct LocatedSnapshot: Sendable {
        let bytes: Data
    }

    static func latest(
        in directory: URL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
    ) throws -> LocatedSnapshot {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey, .isRegularFileKey,
                .isSymbolicLinkKey
            ],
            options: [.skipsHiddenFiles]
        )
        let eligible = try files.compactMap { file -> (URL, Date)? in
            let name = file.lastPathComponent
            guard name.hasPrefix(filenamePrefix),
                  name.lowercased().hasSuffix(".json") else { return nil }
            let values = try file.resourceValues(
                forKeys: [
                    .contentModificationDateKey, .isRegularFileKey,
                    .isSymbolicLinkKey
                ]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else { return nil }
            return (file, values.contentModificationDate ?? .distantPast)
        }
        guard let latest = eligible.sorted(by: {
            if $0.1 == $1.1 { return $0.0.lastPathComponent < $1.0.lastPathComponent }
            return $0.1 > $1.1
        }).first?.0 else {
            throw LookupError.noSnapshot
        }
        let handle = try FileHandle(forReadingFrom: latest)
        defer { try? handle.close() }
        let bytes = try handle.read(
            upToCount: TropLibraryCombinedBackupArchive.maximumBytes + 1
        ) ?? Data()
        guard bytes.count <= TropLibraryCombinedBackupArchive.maximumBytes else {
            throw LookupError.oversized
        }
        guard !bytes.isEmpty else { throw LookupError.invalidFile }
        return LocatedSnapshot(bytes: bytes)
    }
}
