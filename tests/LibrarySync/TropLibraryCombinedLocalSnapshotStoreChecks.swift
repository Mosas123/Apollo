import Foundation

// Strict Swift 6 disk fixture compiles the real production local writer,
// with a controlled validator so it runs without UIKit or the live database.
enum TropLibraryCombinedBackupArchive {
    static let maximumBytes = 4096
}

enum TropLibraryCombinedBackupError: Error {
    case oversized
    case invalid
}

enum TropLibraryCombinedBackupService {
    static func preview(_ data: Data) throws -> Bool {
        guard data == Data("validated combined snapshot".utf8) else {
            throw TropLibraryCombinedBackupError.invalid
        }
        return true
    }
}

enum TropLibraryCombinedLocalSnapshotFinder {
    static let filenamePrefix = "Trop-Combined-Experimental-Snapshot"
}

@main
struct TropLibraryCombinedLocalSnapshotStoreChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("combined-local-save-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = Data("validated combined snapshot".utf8)
        let first = try TropLibraryCombinedLocalSnapshotStore.saveVerified(
            archive, in: directory
        )
        let second = try TropLibraryCombinedLocalSnapshotStore.saveVerified(
            archive, in: directory
        )
        precondition(first != second, "Second save overwrote the first")
        precondition(first.lastPathComponent.hasPrefix(
            TropLibraryCombinedLocalSnapshotFinder.filenamePrefix
        ))
        precondition(first.pathExtension == "json")
        let firstBytes = try Data(contentsOf: first)
        let secondBytes = try Data(contentsOf: second)
        precondition(firstBytes == archive)
        precondition(secondBytes == archive)

        do {
            _ = try TropLibraryCombinedLocalSnapshotStore.saveVerified(
                Data("corrupted payload".utf8), in: directory
            )
            preconditionFailure("Corrupted archive unexpectedly saved")
        } catch TropLibraryCombinedBackupError.invalid {
            // The broken archive must not reach the disk.
        }
        do {
            _ = try TropLibraryCombinedLocalSnapshotStore.saveVerified(
                Data(repeating: 0, count: 4097), in: directory
            )
            preconditionFailure("Oversized archive unexpectedly saved")
        } catch TropLibraryCombinedBackupError.oversized {
            // Guarded before creating another file.
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        precondition(files.count == 2, "Rejected backup created a local file")
        print("Combined local save passed: two intact, unique, verified JSON copies")
    }
}
