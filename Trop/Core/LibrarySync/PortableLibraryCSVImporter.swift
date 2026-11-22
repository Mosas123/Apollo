import CryptoKit
import Foundation

enum PortableLibraryFileError: Error, Equatable, LocalizedError {
    case fileTooLarge
    case invalidEncoding
    case invalidCSV
    case missingTitleColumn
    case missingRows
    case tooManyRows
    case invalidIdentity

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "The library export is too large for this importer."
        case .invalidEncoding: return "The export must be UTF-8 text."
        case .invalidCSV: return "The CSV file is malformed."
        case .missingTitleColumn: return "The export does not contain a song title column."
        case .missingRows: return "The export does not contain any songs."
        case .tooManyRows: return "The export contains too many rows."
        case .invalidIdentity: return "Select a valid destination profile for the import."
        }
    }
}

/// Metadata from a user-owned file, never a playable audio URL. Rows retain
/// their original positions even when they reference the same recording.
struct PortableLibraryCSVRow: Sendable, Equatable {
    let position: Int
    let item: IncomingLibraryItem
    let artist: String?
    let album: String?
}

struct PortableLibraryCSVPreview: Sendable {
    let name: String
    let sourceFileHash: String
    let playlistItem: IncomingLibraryItem?
    let rows: [PortableLibraryCSVRow]

    /// Feed into LibraryImportPlanner.preview; it will deduplicate *library
    /// identities*, not playlist occurrences. Playlist order stays in rows.
    var libraryItems: [IncomingLibraryItem] {
        (playlistItem.map { [$0] } ?? []) + rows.map(\.item)
    }
}

/// Read-only importer for Soundiiz CSV and Spotify Exportify-style CSV files.
/// No network or database writes; caller must explicitly choose an account
/// and review the preview before any future transactional commit.
struct PortableLibraryCSVImporter: Sendable {
    static let maximumBytes = 8 * 1024 * 1024
    static let maximumRows = 25_000
    static let maximumColumns = 64

    func parse(
        data: Data,
        fileName: String,
        destinationAccountID: String,
        importAsPlaylist: Bool = true
    ) throws -> PortableLibraryCSVPreview {
        guard data.count <= Self.maximumBytes else { throw PortableLibraryFileError.fileTooLarge }
        guard !destinationAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              destinationAccountID.count <= 160 else { throw PortableLibraryFileError.invalidIdentity }
        guard var text = String(data: data, encoding: .utf8) else {
            throw PortableLibraryFileError.invalidEncoding
        }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        guard !text.isEmpty else { throw PortableLibraryFileError.missingRows }

        let delimiter = Self.detectDelimiter(text)
        let records = try Self.readRecords(text, delimiter: delimiter)
        guard let header = records.first, header.count <= Self.maximumColumns else {
            throw PortableLibraryFileError.invalidCSV
        }
        let keys = header.map(Self.normalizeHeader)
        let titleIndex = Self.firstIndex(keys, matching: [
            "title", "trackname", "tracktitle", "songname", "song", "track"
        ])
        let artistIndex = Self.firstIndex(keys, matching: [
            "artist", "artists", "artistname", "artistnames", "artistsnames"
        ])
        let albumIndex = Self.firstIndex(keys, matching: ["album", "albumname", "albumtitle"])
        let isrcIndex = Self.firstIndex(keys, matching: ["isrc", "trackisrc"])
        let sourceIndex = Self.firstIndex(keys, matching: ["platform", "service", "source"])
        let identifierIndex = Self.firstIndex(keys, matching: [
            "trackid", "trackuri", "spotifyid", "spotifyuri", "uri"
        ])
        let urlIndex = Self.firstIndex(keys, matching: ["url", "trackurl", "spotifyurl"])

        guard let titleIndex else { throw PortableLibraryFileError.missingTitleColumn }
        let fileHash = Self.sha256(Data(text.utf8))
        let name = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let displayName = name.isEmpty ? "Imported Playlist" : String(name.prefix(120))
        let playlist: IncomingLibraryItem? = importAsPlaylist
            ? IncomingLibraryItem(
                kind: .playlist,
                source: LibrarySourceReference(
                    provider: "portableFile",
                    accountID: destinationAccountID,
                    remoteID: "playlist:\(fileHash)"
                ),
                title: displayName
            ) : nil

        var rows: [PortableLibraryCSVRow] = []
        for record in records.dropFirst() {
            let title = Self.cell(record, at: titleIndex)
            // Do not invent partial identities or silently import unnamed
            // records: users should be warned by the later import UI.
            guard !title.isEmpty else { throw PortableLibraryFileError.invalidCSV }
            guard title.count <= 500 else { throw PortableLibraryFileError.invalidCSV }
            let artist = artistIndex.map { Self.cell(record, at: $0) }.flatMap { $0.isEmpty ? nil : $0 }
            let album = albumIndex.map { Self.cell(record, at: $0) }.flatMap { $0.isEmpty ? nil : $0 }
            let rawISRC = isrcIndex.map { Self.cell(record, at: $0) }
            let normalizedISRC = LibraryImportPlanner.normalizedISRC(rawISRC)
            let rawPlatform = sourceIndex.map { Self.cell(record, at: $0) } ?? ""
            let explicitID = identifierIndex.map { Self.cell(record, at: $0) } ?? ""
            let rawURL = urlIndex.map { Self.cell(record, at: $0) } ?? ""
            let spotifyTrackID = Self.spotifyTrackID(explicitID) ?? Self.spotifyTrackID(rawURL)
            let provider: String
            let remoteID: String

            if let spotifyTrackID {
                provider = "spotify"
                remoteID = spotifyTrackID
            } else if !explicitID.isEmpty, explicitID.count <= 256,
                      let recognized = Self.recognizedProvider(rawPlatform) {
                provider = recognized
                remoteID = explicitID
            } else {
                // File-scoped row fallback prevents title-only records being
                // falsely merged with unrelated editions or other accounts.
                // Reimporting the *same file* yields stable source IDs.
                provider = "portableFile"
                remoteID = "row:\(fileHash):\(rows.count)"
            }
            let item = IncomingLibraryItem(
                kind: .track,
                source: LibrarySourceReference(
                    provider: provider, accountID: destinationAccountID, remoteID: remoteID
                ),
                title: title,
                isrc: normalizedISRC
            )
            rows.append(PortableLibraryCSVRow(
                position: rows.count,
                item: item,
                artist: artist.map { String($0.prefix(500)) },
                album: album.map { String($0.prefix(500)) }
            ))
        }
        guard !rows.isEmpty else { throw PortableLibraryFileError.missingRows }
        // The merge planner counts a playlist as one more input identity.
        guard rows.count + (importAsPlaylist ? 1 : 0) <= LibraryImportPlanner.maximumBatchSize else {
            throw PortableLibraryFileError.tooManyRows
        }
        return PortableLibraryCSVPreview(
            name: displayName, sourceFileHash: fileHash,
            playlistItem: playlist, rows: rows
        )
    }

    private static func recognizedProvider(_ input: String) -> String? {
        switch input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "spotify": return "spotify"
        case "youtube", "youtube music", "youtubemusic": return "youtubeMusic"
        case "apple music", "applemusic": return "appleMusic"
        case "qobuz": return "qobuz"
        case "audius": return "audius"
        case "deezer": return "deezer"
        case "soundcloud": return "soundcloud"
        case "tidal": return "tidal"
        default: return nil
        }
    }

    private static func spotifyTrackID(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: String
        if value.hasPrefix("spotify:track:") {
            id = String(value.dropFirst("spotify:track:".count))
        } else if let url = URL(string: value), url.scheme == "https",
                  url.host == "open.spotify.com",
                  url.pathComponents.count == 3,
                  url.pathComponents[1] == "track" {
            id = url.pathComponents[2]
        } else {
            return nil
        }
        guard id.count == 22,
              id.utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
              }) else { return nil }
        return id
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizeHeader(_ header: String) -> String {
        String(header.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private static func firstIndex(_ headers: [String], matching options: [String]) -> Int? {
        options.compactMap { headers.firstIndex(of: $0) }.first
    }

    private static func cell(_ row: [String], at index: Int) -> String {
        guard row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// RFC-4180-style quoted fields, escaped double quotes, embedded newlines,
    /// BOM, CRLF, comma, semicolon, and tab delimiters. Avoids String.split,
    /// which loses quoted separators and empty trailing fields.
    private static func readRecords(_ text: String, delimiter: Character) throws -> [[String]] {
        // Swift Character treats CRLF as a single grapheme cluster. Normalize
        // before scanning so Windows exports do not collapse into one row.
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var records: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var closedQuote = false
        var index = 0
        func appendRow() throws {
            row.append(field)
            if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                guard row.count <= maximumColumns else { throw PortableLibraryFileError.invalidCSV }
                records.append(row)
                guard records.count <= maximumRows + 1 else { throw PortableLibraryFileError.tooManyRows }
            }
            field = ""
            row = []
            closedQuote = false
        }
        while index < chars.count {
            let ch = chars[index]
            if quoted {
                if ch == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted = false
                        closedQuote = true
                    }
                } else {
                    field.append(ch)
                }
            } else if ch == delimiter {
                row.append(field)
                field = ""
                closedQuote = false
            } else if ch == "\n" {
                try appendRow()
            } else if ch == "\r" {
                if index + 1 >= chars.count || chars[index + 1] != "\n" {
                    try appendRow()
                }
            } else if ch == "\"" && field.isEmpty && !closedQuote {
                quoted = true
            } else if closedQuote && ch != " " && ch != "\t" {
                throw PortableLibraryFileError.invalidCSV
            } else {
                field.append(ch)
            }
            guard field.count <= 4_096 else { throw PortableLibraryFileError.invalidCSV }
            index += 1
        }
        guard !quoted else { throw PortableLibraryFileError.invalidCSV }
        if !row.isEmpty || !field.isEmpty { try appendRow() }
        return records
    }

    private static func detectDelimiter(_ text: String) -> Character {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let header = String(normalized.prefix(4_096).split(separator: "\n", maxSplits: 1).first ?? "")
        let candidates: [Character] = [",", ";", "\t"]
        let counts = candidates.map { delimiter in
            var quoted = false
            var count = 0
            for ch in header {
                if ch == "\"" { quoted.toggle() }
                if !quoted && ch == delimiter { count += 1 }
            }
            return count
        }
        return candidates[counts.firstIndex(of: counts.max() ?? 0) ?? 0]
    }
}
