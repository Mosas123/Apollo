import Foundation

/// Filename allowlist shared by the file importer and the on-disk download
/// reconciliation. This is an audio-only feature, not arbitrary file access.
enum LocalAudioFilePolicy {
    static let supportedExtensions: Set<String> = [
        "m4a", "m4b", "mp3", "aac", "flac", "wav", "aif", "aiff",
        "caf", "ogg", "oga", "opus", "webm", "weba", "ape", "tta",
        "wv", "wma", "mpc", "mp4"
    ]

    static func supports(_ url: URL) -> Bool {
        url.isFileURL
            && supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func mimeHint(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "m4b", "mp4": return "audio/mp4"
        case "flac": return "audio/flac"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "ogg", "oga": return "audio/ogg"
        case "opus": return "audio/opus"
        case "webm", "weba": return "audio/webm"
        default: return nil
        }
    }

    static func isValidAudioSize(_ bytes: Int) -> Bool {
        // Keep the original download integrity threshold; never register a
        // zero-length or truncated external file as an offline song.
        bytes >= 8_192
    }

    static func videoId(from fileName: String) -> String? {
        let stem = (fileName as NSString).deletingPathExtension
        guard let range = stem.range(
            of: #"\[([A-Za-z0-9_:-]{6,})\]$"#,
            options: .regularExpression
        ) else { return nil }
        let token = String(stem[range].dropFirst().dropLast())
        if token.hasPrefix("b64_") {
            return decodeToken(String(token.dropFirst(4)))
        }
        return token
    }

    static func storedFilename(
        title: String,
        videoId: String,
        fileExtension: String
    ) -> String {
        let safeTitle = safeComponent(title.isEmpty ? "audio" : title)
        let token = encodedToken(videoId)
        return "\(safeTitle) [\(token)].\(fileExtension.lowercased())"
    }

    private static func encodedToken(_ value: String) -> String {
        let data = Data(value.utf8).base64EncodedString()
        let token = data
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "b64_\(token)"
    }

    private static func decodeToken(_ token: String) -> String? {
        var value = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value.append("=") }
        guard let data = Data(base64Encoded: value),
              let decoded = String(data: data, encoding: .utf8) else { return nil }
        return decoded
    }

    private static func safeComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(120)).isEmpty ? "audio" : String(cleaned.prefix(120))
    }
}
