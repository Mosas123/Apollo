import Foundation

/// Read-only fallback for files exported to the app's own Documents folder.
/// Unlike the system document picker, this does not need a File Provider
/// extension or security-scoped URL. Never scans other apps' directories.
enum TropLibraryV2LocalSnapshotFinder {
    enum LookupError: Error {
        case noSnapshot
        case invalidFile
    }

    static let filenamePrefix = "Trop-V2-Experimental-Snapshot"

    struct LocatedSnapshot: Sendable {
        let filename: String
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
                .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey
            ],
            options: [.skipsHiddenFiles]
        )

        let candidates = try files.compactMap { url -> (url: URL, date: Date)? in
            let name = url.lastPathComponent
            // Files may append " 2" or " (1)" when the same export name
            // already exists. Only use documents with our reserved prefix.
            guard name.hasPrefix(filenamePrefix), name.lowercased().hasSuffix(".json") else {
                return nil
            }
            let flags = try url.resourceValues(
                forKeys: [
                    .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey
                ]
            )
            guard flags.isRegularFile == true, flags.isSymbolicLink != true else {
                return nil
            }
            return (url, flags.contentModificationDate ?? .distantPast)
        }
        guard let newest = candidates.sorted(by: {
            if $0.date == $1.date {
                return $0.url.lastPathComponent < $1.url.lastPathComponent
            }
            return $0.date > $1.date
        }).first else {
            throw LookupError.noSnapshot
        }

        // This read is strictly bounded even for a file with missing size
        // metadata. The decoded archive applies version, SHA-256 and schema
        // validation before showing any successful result to the user.
        let handle = try FileHandle(forReadingFrom: newest.url)
        defer { try? handle.close() }
        let bytes = try handle.read(
            upToCount: TropLibraryV2RecoveryArchive.maximumBytes + 1
        ) ?? Data()
        guard bytes.count <= TropLibraryV2RecoveryArchive.maximumBytes else {
            throw TropLibraryV2RecoveryError.oversized
        }
        guard !bytes.isEmpty else { throw LookupError.invalidFile }
        return LocatedSnapshot(filename: newest.url.lastPathComponent, bytes: bytes)
    }
}
