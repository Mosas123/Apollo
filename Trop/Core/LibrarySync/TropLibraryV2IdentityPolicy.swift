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


/// The first V2 playback slice accepts only an explicitly saved, unambiguous
/// provider-scoped audio ID. This intentionally does not infer one from title,
/// artist, Trop UUID, a MusicBrainz metadata ID or a legacy YouTube video ID.
/// YouTube audio can be added later behind an explicit opt-in and music-only
/// provenance gate; it must never become an implicit fallback.
enum TropLibraryV2PlaybackSourceError: Error, Equatable, LocalizedError {
    case unavailable
    case ambiguous

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This song has no verified independent audio source yet. It stays saved in your library."
        case .ambiguous:
            return "More than one audio source is linked to this song. Choose a source before playing."
        }
    }
}

enum TropLibraryV2PlaybackSourcePolicy {
    /// Only full-track sources with a dedicated non-YouTube playback route.
    private static let supportedProviders: Set<String> = [
        "audius", "qobuz", "jiosaavn", "addon"
    ]

    static func playbackKey(for aliases: [TropLibraryV2SourceAlias]) throws -> String {
        let candidates = Set(aliases.compactMap { alias -> String? in
            guard alias.scope == "global",
                  supportedProviders.contains(alias.provider) else { return nil }
            return "\(alias.provider):\(alias.externalID)"
        })
        guard !candidates.isEmpty else {
            throw TropLibraryV2PlaybackSourceError.unavailable
        }
        guard candidates.count == 1, let key = candidates.first else {
            throw TropLibraryV2PlaybackSourceError.ambiguous
        }
        return key
    }
}
