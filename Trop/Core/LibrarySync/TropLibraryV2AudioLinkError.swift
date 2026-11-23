import Foundation

enum TropLibraryV2AudioLinkError: Error, LocalizedError, Equatable {
    case notVerified
    case usedByAnotherRecording
    case existingSource

    var errorDescription: String? {
        switch self {
        case .notVerified:
            return "This result could not be verified against the saved recording. Nothing was changed."
        case .usedByAnotherRecording:
            return "This audio source is already linked to a different saved song."
        case .existingSource:
            return "This song already has an independent audio source. Source switching is not available yet."
        }
    }
}
