import Foundation

/// The library owns stable UUIDs. Playback providers are optional aliases,
/// never account identities or the primary key of a saved item.
enum TropLibraryV2Kind: String, Codable, CaseIterable, Sendable {
    case recording
    case album
    case artist
    case playlist
    case podcast
    case episode
}

enum TropLibraryV2ValidationError: Error, Equatable, Sendable {
    case invalidTitle
    case invalidIdentifier
    case invalidProvider
    case invalidSourceScope
    case invalidAlias
    case unexpectedItemKind
    case missingItem
}

struct TropLibraryV2SourceAlias: Equatable, Sendable {
    let provider: String
    let scope: String
    let externalID: String

    /// Scope may identify an authorized import or provider account, but
    /// cannot contain URLs, credentials, spaces or control characters.
    init(provider: String, scope: String = "global", externalID: String) throws {
        guard Self.isSafeToken(provider, maximum: 64) else {
            throw TropLibraryV2ValidationError.invalidProvider
        }
        guard Self.isSafeToken(scope, maximum: 160) else {
            throw TropLibraryV2ValidationError.invalidSourceScope
        }
        guard Self.isSafeExternalID(externalID) else {
            throw TropLibraryV2ValidationError.invalidAlias
        }
        self.provider = provider
        self.scope = scope
        self.externalID = externalID
    }

    private static func isSafeToken(_ value: String, maximum: Int) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximum else { return false }
        return value.utf8.allSatisfy {
            (48...57).contains($0) || (97...122).contains($0)
                || $0 == 45 || $0 == 95 || $0 == 46
        }
    }

    private static func isSafeExternalID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 512,
              !value.contains("://"), !value.contains("?"),
              !value.contains("#"), !value.contains("\\"),
              !value.hasPrefix("/"),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return false }
        return true
    }
}

enum TropLibraryV2IdentityPolicy {
    static func newID() -> String { UUID().uuidString.lowercased() }

    static func isCanonicalID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }

    static func checkedTitle(_ value: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title.utf8.count <= 1_024,
              !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw TropLibraryV2ValidationError.invalidTitle }
        return title
    }

    static func checkedOptionalText(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.utf8.count <= 1_024,
              !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw TropLibraryV2ValidationError.invalidTitle }
        return normalized.isEmpty ? nil : normalized
    }

    static func checkedID(_ value: String) throws -> String {
        guard isCanonicalID(value) else {
            throw TropLibraryV2ValidationError.invalidIdentifier
        }
        return value
    }
}


/// One recording may have several provider links. Resolve the playable
/// source deterministically for the current quality instead of conflating
/// a Trop UUID with a provider track ID. No remote catalogue is queried here.
enum TropLibraryV2PlaybackSourceError: Error, Equatable, LocalizedError {
    case unavailable
    case ambiguous
    case incompatibleQuality

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "No verified audio source is available right now. "
                + "Your song stays saved. Review alternatives from its menu."
        case .ambiguous:
            return "Multiple editions need your approval. The song stays saved."
        case .incompatibleQuality:
            return "No linked source meets this audio-quality setting. "
                + "Your song stays saved."
        }
    }
}

enum TropLibraryV2PlaybackSourcePolicy {
    private static let supportedProviders: Set<String> = [
        "audius", "qobuz", "jiosaavn", "addon"
    ]
    private static let alternateScope = "user-approved-alt"

    /// YouTube is an optional AUDIO transport for previously saved IDs,
    /// never a mandatory catalogue or login dependency. Reject arbitrary
    /// non-video strings, provider-specific IDs, URLs and query fragments.
    private static func youtubeIDIsSafe(_ value: String) -> Bool {
        value.utf8.count == 11 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0)
                || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    static func playbackKey(
        for aliases: [TropLibraryV2SourceAlias],
        requiresLossless: Bool = false,
        allowYouTubeAudio: Bool = false,
        preferHigh: Bool = false
    ) throws -> String {
        struct Option {
            let key: String
            let provider: String
            let isAlternate: Bool
        }
        let options: [Option] = aliases.compactMap { alias in
            guard alias.scope == "global" || alias.scope == alternateScope else {
                return nil
            }
            if supportedProviders.contains(alias.provider) {
                return Option(
                    key: "\(alias.provider):\(alias.externalID)",
                    provider: alias.provider,
                    isAlternate: alias.scope == alternateScope
                )
            }
            if alias.provider == "youtube" && allowYouTubeAudio,
               alias.scope == "global",
               youtubeIDIsSafe(alias.externalID) {
                return Option(
                    key: alias.externalID, provider: "youtube",
                    isAlternate: false
                )
            }
            return nil
        }
        guard !options.isEmpty else {
            throw TropLibraryV2PlaybackSourceError.unavailable
        }
        let eligible = options.filter {
            !requiresLossless || $0.provider == "addon" || $0.provider == "qobuz"
        }
        guard !eligible.isEmpty else {
            throw TropLibraryV2PlaybackSourceError.incompatibleQuality
        }
        // Qobuz has an independently verified CD FLAC route; addon output
        // still needs format verification when its stream is actually opened.
        // Do not claim that a source supports Hi-Res or Atmos by its name.
        let priority: [String]
        if requiresLossless {
            priority = ["qobuz", "addon"]
        } else if preferHigh {
            priority = ["qobuz", "addon", "jiosaavn", "audius", "youtube"]
        } else {
            priority = ["addon", "qobuz", "youtube", "jiosaavn", "audius"]
        }
        // Exact links win over expressly approved alternate versions.
        return eligible.sorted {
            if $0.isAlternate != $1.isAlternate {
                return !$0.isAlternate
            }
            let left = priority.firstIndex(of: $0.provider) ?? priority.count
            let right = priority.firstIndex(of: $1.provider) ?? priority.count
            if left != right { return left < right }
            return $0.key < $1.key
        }[0].key
    }
}
