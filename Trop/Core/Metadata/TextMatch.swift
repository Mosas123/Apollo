import Foundation

/// Matching helpers for cross-catalogue metadata. YouTube names differ a lot
/// from Apple/Deezer: auto-generated channels are "Artist - Topic", labels add
/// "VEVO", "Official", "Music", "Records", and tracks carry "(Official Video)",
/// "feat. …", "- Remastered", etc. These helpers strip that noise so the same
/// recording matches across sources — and, just as important, so we *don't*
/// grab a wrong cover ("Drake" must not match "Drake Bell").
enum TextMatch {
    private static let suffixWords: [String] = [
        "official artist channel", "official music video", "official video",
        "official audio", "official", "vevo", "topic", "music", "records",
        "recordings", "channel", "tv"
    ]

    /// Lowercase, diacritic-insensitive, punctuation-light key.
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// Song title without bracketed qualifiers or a trailing "feat. …".
    static func normalizeTitle(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(
            of: "\\s*[\\[(][^\\])]*[\\])]", with: "", options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "\\s+(-\\s+)?(feat\\.?|ft\\.?|featuring)\\s+.*$",
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        // Drop trailing " - Remastered 2011", "- Live", "- Radio Edit"
        text = text.replacingOccurrences(
            of: "\\s+-\\s+(remaster(ed)?|live|radio edit|album version|single version).*$",
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        // Album editions: "Deluxe Edition", "Special Edition", …
        text = text.replacingOccurrences(
            of: "\\b(deluxe|special|expanded|anniversary|bonus) (edition|version)\\b.*$",
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        return normalize(text)
    }

    /// Primary artist name, without channel suffixes or featured acts.
    static func normalizeArtist(_ value: String) -> String {
        var text = value
        // "Artist - Topic" (YouTube auto-generated channel)
        text = text.replacingOccurrences(
            of: "\\s+-\\s*topic\\s*$", with: "", options: [.regularExpression, .caseInsensitive]
        )
        // Take the first act when several are listed.
        for separator in [" feat. ", " feat ", " ft. ", " ft ", " featuring ", " & ", " x "] {
            if let range = text.range(of: separator, options: .caseInsensitive) {
                text = String(text[..<range.lowerBound])
            }
        }
        if let comma = text.firstIndex(of: ",") {
            text = String(text[..<comma])
        }
        var words = normalize(text).split(separator: " ").map(String.init)
        // Trim leading "the"
        if words.first == "the" { words.removeFirst() }
        // Strip known channel/label words from the end.
        while let last = words.last, suffixWords.contains(last) {
            words.removeLast()
        }
        // "AdeleVEVO" (no space) → "adele"
        if words.count == 1, let only = words.first, only.count > 4, only.hasSuffix("vevo") {
            words[0] = String(only.dropLast(4))
        }
        return words.joined(separator: " ")
    }

    /// Artist name to use in a catalogue query (keeps casing, strips noise).
    static func queryArtist(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(
            of: "\\s+-\\s*topic\\s*$", with: "", options: [.regularExpression, .caseInsensitive]
        )
        for separator in [" feat. ", " feat ", " ft. ", " ft ", " featuring "] {
            if let range = text.range(of: separator, options: .caseInsensitive) {
                text = String(text[..<range.lowerBound])
            }
        }
        for word in suffixWords {
            text = text.replacingOccurrences(
                of: "\\s+\(word)\\s*$", with: "", options: [.regularExpression, .caseInsensitive]
            )
        }
        // Concatenated "ArtistVEVO" / "ArtistOfficial".
        text = text.replacingOccurrences(
            of: "(?<=[a-z0-9])(vevo|official)$", with: "", options: [.regularExpression, .caseInsensitive]
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizeTitle(lhs)
        let b = normalizeTitle(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        // Containment only for reasonably long strings, to avoid "Intro" hits.
        if a.count >= 4, b.count >= 4 {
            return a.contains(b) || b.contains(a)
        }
        return false
    }

    /// Karaoke/tribute/sped-up uploads that pollute catalogue matches.
    static func isSuspiciousVersion(_ title: String) -> Bool {
        let text = normalizeTitle(title)
        let markers = [
            "karaoke", "tribute", "made famous", "instrumental",
            "8d audio", "sped up", "nightcore", "reverb",
            "in the style of", "cover by", "originally performed"
        ]
        return markers.contains { text.contains($0) }
    }

    static func albumsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizeTitle(lhs)
        let b = normalizeTitle(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        if a.count >= 4, b.count >= 4 {
            return a.contains(b) || b.contains(a)
        }
        return false
    }

    static func artistsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizeArtist(lhs)
        let b = normalizeArtist(rhs)
        guard !a.isEmpty, !b.isEmpty else { return true }
        if a == b { return true }
        let aTokens = a.split(separator: " ")
        let bTokens = b.split(separator: " ")
        // "Drake" vs "Drake Bell" must NOT match: only allow containment when
        // the shorter name has at least two words ("New Order" in "New Order UK").
        if min(aTokens.count, bTokens.count) >= 2 {
            return a.contains(b) || b.contains(a)
        }
        return false
    }
}
