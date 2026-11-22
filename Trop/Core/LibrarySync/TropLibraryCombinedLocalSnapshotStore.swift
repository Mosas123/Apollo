import Foundation

/// Creates a durable, user-visible metadata archive inside the app's Documents
/// directory. This is a local COPY, never a move, overwrite, database restore
/// or deletion. The Files app may expose this directory as "Thrum"; users can
/// also export copies via the in-app document exporter if Files hides it.
enum TropLibraryCombinedLocalSnapshotStore {
    /// Validate again at the write boundary, not only in the caller's UI.
    /// Every save has a unique name, preserving all earlier snapshots.
    static func saveVerified(
        _ bytes: Data,
        in directory: URL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
    ) throws -> URL {
        guard !bytes.isEmpty,
              bytes.count <= TropLibraryCombinedBackupArchive.maximumBytes else {
            throw TropLibraryCombinedBackupError.oversized
        }
        _ = try TropLibraryCombinedBackupService.preview(bytes)

        let fm = FileManager.default
        try fm.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(TropLibraryCombinedLocalSnapshotFinder.filenamePrefix)"
            + "-\(timestamp)-\(UUID().uuidString).json"
        let destination = directory.appendingPathComponent(filename)
        // No overwrites even if a future naming implementation changes.
        guard !fm.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try bytes.write(to: destination, options: .atomic)

        // Prove that the saved on-disk copy remains intact. If verification
        // fails, report an error; do not delete or modify prior backups.
        let reread = try Data(contentsOf: destination)
        _ = try TropLibraryCombinedBackupService.preview(reread)
        return destination
    }
}
