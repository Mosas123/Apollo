import Foundation

struct PlaylistCSVRow: Sendable, Equatable {
    let title: String
    let artist: String
    let album: String?
    let durationSeconds: Int
    let thumbnailURL: String?
    let isExplicit: Bool
    let spotifyTrackID: String?
    let isrc: String?
}

struct PlaylistCSVFile: Sendable {
    let name: String
    let rows: [PlaylistCSVRow]
}

enum PlaylistCSVError: Error, LocalizedError {
    case tooLarge
    case invalidEncoding
    case empty
    case missingTitle
    case malformed

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "The CSV is too large."
        case .invalidEncoding: return "The CSV is not UTF-8 text."
        case .empty: return "The CSV does not contain any songs."
        case .missingTitle: return "The CSV has no song title column."
        case .malformed: return "The CSV is malformed."
        }
    }
}

/// Reads Exportify, Soundiiz and generic playlist CSV exports. Metadata only:
/// audio is always resolved later through Apollo's normal catalogue pipeline.
struct PlaylistCSVImporter: Sendable {
    static let maximumBytes = 8 * 1024 * 1024
    static let maximumRows = 5_000

    func parse(data: Data, fileName: String) throws -> PlaylistCSVFile {
        guard data.count <= Self.maximumBytes else { throw PlaylistCSVError.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else {
            throw PlaylistCSVError.invalidEncoding
        }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlaylistCSVError.empty
        }

        let delimiter = Self.detectDelimiter(text)
        let records = try Self.readRecords(text, delimiter: delimiter)
        guard let header = records.first, !header.isEmpty else { throw PlaylistCSVError.malformed }
        let keys = header.map(Self.normalizeHeader)
        let titleIndex = Self.index(keys, aliases: [
            "trackname", "title", "songname", "song", "name"
        ])
        let artistIndex = Self.index(keys, aliases: [
            "artistnames", "artistname", "artists", "artist"
        ])
        let albumIndex = Self.index(keys, aliases: ["albumname", "album", "albumtitle"])
        let durationIndex = Self.index(keys, aliases: [
            "trackdurationms", "durationms", "trackduration", "duration"
        ])
        let thumbnailIndex = Self.index(keys, aliases: [
            "albumimageurl", "imageurl", "artworkurl", "thumbnailurl", "cover"
        ])
        let explicitIndex = Self.index(keys, aliases: ["explicit", "isexplicit"])
        let uriIndex = Self.index(keys, aliases: [
            "trackuri", "spotifyuri", "trackid", "spotifyid", "uri", "url"
        ])
        let isrcIndex = Self.index(keys, aliases: ["isrc", "trackisrc"])
        guard let titleIndex else { throw PlaylistCSVError.missingTitle }

        var rows: [PlaylistCSVRow] = []
        for record in records.dropFirst() {
            guard rows.count < Self.maximumRows else { break }
            let title = Self.cell(record, titleIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let artist = artistIndex.map { Self.cell(record, $0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let album = albumIndex.map { Self.cell(record, $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            let duration = durationIndex.map { Self.seconds(from: Self.cell(record, $0), header: keys[$0]) } ?? 0
            let thumbnail = thumbnailIndex.map { Self.cell(record, $0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let explicit = explicitIndex.map { Self.boolean(Self.cell(record, $0)) } ?? false
            let uri = uriIndex.map { Self.cell(record, $0) } ?? ""
            let spotifyID = Self.spotifyTrackID(from: uri)
            let isrc = isrcIndex.map { Self.cell(record, $0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }

            rows.append(PlaylistCSVRow(
                title: title,
                artist: artist,
                album: (album?.isEmpty == true ? nil : album),
                durationSeconds: duration,
                thumbnailURL: thumbnail,
                isExplicit: explicit,
                spotifyTrackID: spotifyID,
                isrc: isrc
            ))
        }

        guard !rows.isEmpty else { throw PlaylistCSVError.empty }
        let name = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return PlaylistCSVFile(
            name: name.isEmpty ? "Imported Playlist" : String(name.prefix(120)),
            rows: rows
        )
    }

    private static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let candidates: [Character] = [",", ";", "\t"]
        return candidates.max { lhs, rhs in
            firstLine.filter { $0 == lhs }.count < firstLine.filter { $0 == rhs }.count
        } ?? ","
    }

    private static func readRecords(_ text: String, delimiter: Character) throws -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case delimiter:
                    record.append(field)
                    field = ""
                case "\n":
                    record.append(field)
                    records.append(record)
                    record = []
                    field = ""
                case "\r":
                    break
                default:
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }
        if inQuotes { throw PlaylistCSVError.malformed }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func index(_ keys: [String], aliases: [String]) -> Int? {
        for alias in aliases {
            if let index = keys.firstIndex(of: alias) { return index }
        }
        return nil
    }

    private static func cell(_ record: [String], _ index: Int) -> String {
        record.indices.contains(index) ? record[index] : ""
    }

    private static func boolean(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1", "explicit", "x": return true
        default: return false
        }
    }

    private static func seconds(from value: String, header: String) -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
            if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        }
        guard let number = Double(trimmed) else { return 0 }
        if header.contains("ms") { return Int(number / 1000) }
        return Int(number > 1_000 ? number / 1000 : number)
    }

    private static func spotifyTrackID(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("spotify:track:") {
            return String(trimmed.dropFirst("spotify:track:".count))
        }
        if let range = trimmed.range(of: "/track/") {
            let tail = trimmed[range.upperBound...]
            return tail.split(whereSeparator: { $0 == "?" || $0 == "/" }).first.map(String.init)
        }
        if trimmed.count == 22, trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return trimmed
        }
        return nil
    }
}
