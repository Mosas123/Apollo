import Foundation

enum MusicVersion: String, Sendable {
    case clean
    case explicit
    case unknown
}

/// Clean and explicit releases usually share the same title; catalogues strip
/// "(Clean)" before matching. Detect the version from the original label and
/// never let a clean carrier satisfy an explicit request (or the reverse).
enum MusicVersionPolicy {
    private static let explicitMarkers = [
        "explicit", "dirty", "uncensored", "unclean", "parental advisory"
    ]
    private static let cleanMarkers = [
        "clean", "censored", "radio edit", "radio version",
        "kidz bop", "family friendly", "edited", "no swearing"
    ]

    static func version(in title: String) -> MusicVersion {
        let lower = title.lowercased()
        let groups = bracketedGroups(in: lower)
        let label = groups.isEmpty ? "" : groups.joined(separator: " ")

        if containsAny(explicitMarkers, in: label) { return .explicit }
        if containsAny(cleanMarkers, in: label) { return .clean }

        // "Song - Clean" / "Song – Explicit" without brackets.
        if lower.range(
            of: #"\s[-–]\s*(clean|censored|edited|radio edit|radio version)\b"#,
            options: .regularExpression
        ) != nil {
            return .clean
        }
        if lower.range(
            of: #"\s[-–]\s*(explicit|dirty|uncensored)\b"#,
            options: .regularExpression
        ) != nil {
            return .explicit
        }
        return .unknown
    }

    static func isCompatible(candidateTitle: String, requestedExplicit: Bool) -> Bool {
        switch version(in: candidateTitle) {
        case .clean: return !requestedExplicit
        case .explicit: return requestedExplicit
        case .unknown: return true
        }
    }

    static func scoreBonus(candidateTitle: String, requestedExplicit: Bool) -> Int {
        switch version(in: candidateTitle) {
        case .explicit: return requestedExplicit ? 12 : 0
        case .clean: return requestedExplicit ? 0 : 6
        case .unknown: return 0
        }
    }

    private static func bracketedGroups(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[\[(]([^\])]*)[\])]"#
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func containsAny(_ markers: [String], in text: String) -> Bool {
        markers.contains { text.contains($0) }
    }
}
