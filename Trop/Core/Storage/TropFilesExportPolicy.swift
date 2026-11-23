import Foundation

/// Copies are exported only when the user requests them. Never move files
/// used for playback, and never treat a file-sharing plist key as proof that
/// Files exposes the sandbox in every sideloaded iOS installation.
enum TropFilesExportPolicy {
    struct StagedLogs {
        let files: [URL]
        let directory: URL
    }

    enum ExportError: LocalizedError {
        case noLogs
        case logTooLarge

        var errorDescription: String? {
            switch self {
            case .noLogs: return "No current or previous log is available yet."
            case .logTooLarge: return "A log is unexpectedly large. Export was cancelled."
            }
        }
    }

    static func safeDownloadedAudioURL(
        storedPath: String, downloadsDirectory: URL
    ) -> URL? {
        guard !storedPath.isEmpty, !storedPath.contains("\0") else {
            return nil
        }
        let root = downloadsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let original = storedPath.hasPrefix("/")
            ? URL(fileURLWithPath: storedPath)
            : downloadsDirectory.appendingPathComponent(storedPath)
        let lexical = original.standardizedFileURL
        let prefix = root.path + "/"
        // Check both the requested path and the resolved path: a malicious or
        // stale database path must not export files outside Downloads.
        guard lexical.path.hasPrefix(prefix) else { return nil }
        let real = lexical.resolvingSymlinksInPath()
        guard real.path.hasPrefix(prefix) else { return nil }
        let allowed: Set<String> = [
            "flac", "m4a", "mp3", "aac", "opus", "ogg", "wav", "aiff"
        ]
        guard allowed.contains(real.pathExtension.lowercased()),
              let attributes = try? FileManager.default.attributesOfItem(atPath: real.path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            return nil
        }
        return real
    }

    /// Best-effort privacy filter. Users must still inspect diagnostic files
    /// before sharing them externally. Never upload exports automatically.
    static func sanitizedLog(_ contents: String) -> String {
        contents.components(separatedBy: .newlines).map { line in
            let lower = line.lowercased()
            let sensitive = [
                "authorization", "cookie", "token=", "token:", "secret",
                "password", "apikey", "api_key", "manifest", "bearer ",
                "client_secret", "session_key"
            ]
            if sensitive.contains(where: lower.contains) {
                return "[REDACTED: sensitive log line]"
            }
            var safe = line
            for pattern in [
                #"(?:https?|file)://[^\s"'<>]+"#,
                #"(?:/private/var|/var/mobile|/Users/)[^\s"'<>]+"#,
                #"addon:[A-Za-z0-9+/_=:%-]{8,}"#
            ] {
                safe = safe.replacingOccurrences(
                    of: pattern, with: "[REDACTED]",
                    options: [.regularExpression, .caseInsensitive]
                )
            }
            return safe
        }.joined(separator: "\n")
    }

    static func stageSanitizedLogs(
        documents: URL, temporaryDirectory: URL
    ) throws -> StagedLogs {
        let originals = [
            ("log.txt", "Thrum-log-sanitized.txt"),
            ("log.previous.txt", "Thrum-log-previous-sanitized.txt")
        ]
        let fm = FileManager.default
        let destination = temporaryDirectory.appendingPathComponent(
            "Thrum-Log-Export-" + UUID().uuidString, isDirectory: true
        )
        var files: [URL] = []
        do {
            for (name, exportName) in originals {
                let source = documents.appendingPathComponent(name)
                guard fm.fileExists(atPath: source.path) else { continue }
                let info = try fm.attributesOfItem(atPath: source.path)
                guard (info[.type] as? FileAttributeType) == .typeRegular else {
                    continue
                }
                let bytes = (info[.size] as? NSNumber)?.intValue ?? 0
                guard bytes <= 2_000_000 else { throw ExportError.logTooLarge }
                let data = try Data(contentsOf: source)
                guard data.count <= 2_000_000 else {
                    throw ExportError.logTooLarge
                }
                if files.isEmpty {
                    try fm.createDirectory(
                        at: destination, withIntermediateDirectories: true
                    )
                }
                let safe = sanitizedLog(
                    String(decoding: data, as: UTF8.self)
                )
                let target = destination.appendingPathComponent(exportName)
                try Data(safe.utf8).write(to: target, options: [.atomic])
                files.append(target)
            }
            guard !files.isEmpty else { throw ExportError.noLogs }
            return StagedLogs(files: files, directory: destination)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }
}
