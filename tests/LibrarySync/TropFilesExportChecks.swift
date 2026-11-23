import Foundation

@main
struct TropFilesExportChecks {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(
            "Thrum-Export-Checks-" + UUID().uuidString, isDirectory: true
        )
        defer { try? fm.removeItem(at: base) }
        let docs = base.appendingPathComponent("Documents")
        let downloads = docs.appendingPathComponent("Downloads")
        let temp = base.appendingPathComponent("Temporary")
        try fm.createDirectory(
            at: downloads, withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: temp, withIntermediateDirectories: true
        )

        let song = downloads.appendingPathComponent(
            "A Song [opaque].flac"
        )
        try Data([0x66, 0x4C, 0x61, 0x43]).write(to: song)
        let outside = docs.appendingPathComponent("private.flac")
        try Data("private".utf8).write(to: outside)
        let safeRelative = TropFilesExportPolicy.safeDownloadedAudioURL(
            storedPath: song.lastPathComponent, downloadsDirectory: downloads
        )
        let safeAbsolute = TropFilesExportPolicy.safeDownloadedAudioURL(
            storedPath: song.path, downloadsDirectory: downloads
        )
        precondition(safeRelative?.path == song.path)
        precondition(safeAbsolute?.path == song.path)
        precondition(TropFilesExportPolicy.safeDownloadedAudioURL(
            storedPath: "../private.flac", downloadsDirectory: downloads
        ) == nil)
        precondition(TropFilesExportPolicy.safeDownloadedAudioURL(
            storedPath: outside.path, downloadsDirectory: downloads
        ) == nil)
        precondition(TropFilesExportPolicy.safeDownloadedAudioURL(
            storedPath: "missing.flac", downloadsDirectory: downloads
        ) == nil)
        let dangerousLink = downloads.appendingPathComponent("outside.flac")
        try fm.createSymbolicLink(
            at: dangerousLink, withDestinationURL: outside
        )
        precondition(TropFilesExportPolicy.safeDownloadedAudioURL(
            storedPath: dangerousLink.lastPathComponent,
            downloadsDirectory: downloads
        ) == nil)
        let invalid = downloads.appendingPathComponent("secrets.txt")
        try Data("private".utf8).write(to: invalid)
        precondition(TropFilesExportPolicy.safeDownloadedAudioURL(
            storedPath: invalid.lastPathComponent,
            downloadsDirectory: downloads
        ) == nil)

        let original = """
        [09:15] playback started GET https://private.example/song?signature=secret
        [09:16] addon:privateBase64IdentifierThatMustNotLeak
        [09:17] Authorization: Bearer very_private_key
        [09:18] source /private/var/mobile/Containers/Data/id/song.flac
        [09:19] firstPlaying ms=930
        """
        try Data(original.utf8).write(
            to: docs.appendingPathComponent("log.txt")
        )
        try Data("cookie=private_value\n".utf8).write(
            to: docs.appendingPathComponent("log.previous.txt")
        )
        let sanitized = TropFilesExportPolicy.sanitizedLog(original)
        precondition(!sanitized.contains("private.example"))
        precondition(!sanitized.contains("privateBase64Identifier"))
        precondition(!sanitized.contains("Bearer very_private"))
        precondition(!sanitized.contains("/private/var/mobile"))
        precondition(sanitized.contains("firstPlaying ms=930"))

        let staged = try TropFilesExportPolicy.stageSanitizedLogs(
            documents: docs, temporaryDirectory: temp
        )
        defer { try? fm.removeItem(at: staged.directory) }
        precondition(staged.files.count == 2)
        let exposed = try staged.files.map { try String(contentsOf: $0, encoding: .utf8) }
        precondition(!exposed.joined().contains("private.example"))
        precondition(!exposed.joined().contains("private_value"))
        precondition(try String(
            contentsOf: docs.appendingPathComponent("log.txt"),
            encoding: .utf8
        ) == original)
        precondition(try Data(contentsOf: song) == Data([0x66, 0x4C, 0x61, 0x43]))
        print("Trop Files exports passed: sandbox, no symlink escape, log redaction, read-only originals")
    }
}
