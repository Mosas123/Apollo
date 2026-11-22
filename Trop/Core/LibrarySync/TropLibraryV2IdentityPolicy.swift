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
