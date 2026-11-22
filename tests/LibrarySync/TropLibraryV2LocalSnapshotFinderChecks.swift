import Foundation

@main
enum TropLibraryV2LocalSnapshotFinderChecks {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("trop-v2-local-check-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        // A valid empty library archive is sufficient to exercise the
        // local picker-free path without storing user data in test fixtures.
        let empty = TropLibraryV2RecoverySnapshot(
            items: [], aliases: [], playlistEntries: [],
            radioFavorites: [], importLedger: [], legacyRelations: [],
            omittedPrivateAliases: 0
        )
        let archive = try TropLibraryV2RecoveryArchive.encode(empty)

        let first = root.appendingPathComponent("Trop-V2-Experimental-Snapshot.json")
        let newer = root.appendingPathComponent("Trop-V2-Experimental-Snapshot (1).json")
        try archive.write(to: first)
        try archive.write(to: newer)
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: first.path
        )
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newer.path
        )
        let located = try TropLibraryV2LocalSnapshotFinder.latest(in: root)
        precondition(located.filename == newer.lastPathComponent)
        precondition(try TropLibraryV2RecoveryArchive.decode(located.bytes).library == empty)

        // Unrelated files, similarly named text and directories are skipped.
        try Data("fake".utf8).write(
            to: root.appendingPathComponent("Trop-V2-Experimental-Snapshot.txt")
        )
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Trop-V2-Experimental-Snapshot-dir.json"),
            withIntermediateDirectories: true
        )
        let symlink = root.appendingPathComponent(
            "Trop-V2-Experimental-Snapshot-symlink.json"
        )
        try fileManager.createSymbolicLink(at: symlink, withDestinationURL: first)
        precondition(
            try TropLibraryV2LocalSnapshotFinder.latest(in: root).filename
                == newer.lastPathComponent
        )

        // No report of success for an absent snapshot.
        try fileManager.removeItem(at: first)
        try fileManager.removeItem(at: newer)
        do {
            _ = try TropLibraryV2LocalSnapshotFinder.latest(in: root)
            preconditionFailure("Must refuse missing archive")
        } catch TropLibraryV2LocalSnapshotFinder.LookupError.noSnapshot {}

        // A huge file never gets fully loaded, even if the file provider's
        // advertised size is unavailable.
        let oversized = root.appendingPathComponent(
            "Trop-V2-Experimental-Snapshot.json"
        )
        precondition(fileManager.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        handle.truncateFile(
            atOffset: UInt64(TropLibraryV2RecoveryArchive.maximumBytes + 100)
        )
        try handle.close()
        do {
            _ = try TropLibraryV2LocalSnapshotFinder.latest(in: root)
            preconditionFailure("Must reject oversized archive")
        } catch TropLibraryV2RecoveryError.oversized {}

        print("Picker-free local V2 snapshot discovery, selection and size checks passed")
    }
}
