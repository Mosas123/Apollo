import Foundation

@main
enum TropLibraryCombinedLocalSnapshotFinderChecks {
    static func main() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(
            "combined-local-archive-\(UUID().uuidString)", isDirectory: true
        )
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }

        let old = folder.appendingPathComponent(
            "Trop-Combined-Experimental-Snapshot.json"
        )
        let recent = folder.appendingPathComponent(
            "Trop-Combined-Experimental-Snapshot (1).json"
        )
        try Data("old".utf8).write(to: old)
        try Data("new".utf8).write(to: recent)
        try fm.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: old.path
        )
        try fm.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: recent.path
        )
        let found = try TropLibraryCombinedLocalSnapshotFinder.latest(in: folder)
        precondition(found.bytes == Data("new".utf8))

        // Do not follow symlinks, choose directories, or read unrelated files.
        try fm.createDirectory(
            at: folder.appendingPathComponent(
                "Trop-Combined-Experimental-Snapshot-dir.json"
            ),
            withIntermediateDirectories: true
        )
        try fm.createSymbolicLink(
            at: folder.appendingPathComponent(
                "Trop-Combined-Experimental-Snapshot-link.json"
            ),
            withDestinationURL: old
        )
        try Data("wrong".utf8).write(
            to: folder.appendingPathComponent(
                "Trop-Combined-Experimental-Snapshot.txt"
            )
        )
        let second = try TropLibraryCombinedLocalSnapshotFinder.latest(in: folder)
        precondition(second.bytes == Data("new".utf8))

        try fm.removeItem(at: old)
        try fm.removeItem(at: recent)
        do {
            _ = try TropLibraryCombinedLocalSnapshotFinder.latest(in: folder)
            preconditionFailure("Missing combined archive was accepted")
        } catch TropLibraryCombinedLocalSnapshotFinder.LookupError.noSnapshot {}

        // A sparse oversized file must be rejected after a bounded read;
        // the test does not allocate 40 MiB in memory.
        let huge = folder.appendingPathComponent(
            "Trop-Combined-Experimental-Snapshot.json"
        )
        precondition(fm.createFile(atPath: huge.path, contents: nil))
        let handle = try FileHandle(forWritingTo: huge)
        handle.truncateFile(
            atOffset: UInt64(TropLibraryCombinedBackupArchive.maximumBytes + 4)
        )
        try handle.close()
        do {
            _ = try TropLibraryCombinedLocalSnapshotFinder.latest(in: folder)
            preconditionFailure("Oversized combined archive was accepted")
        } catch TropLibraryCombinedLocalSnapshotFinder.LookupError.oversized {}

        print("Combined snapshot local finder: newest file, symlink and size guards passed")
    }
}
