import Foundation

/// A connectivity failure does not turn provider-metadata-only favorites,
/// playlists or radio stations into playable offline content.
enum TropOfflineHomePolicy {
    static func isDisconnected(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            && (nsError.code == NSURLErrorNotConnectedToInternet
                || nsError.code == NSURLErrorNetworkConnectionLost)
    }

    static func showDownloads(
        libraryV2Enabled: Bool,
        isDisconnected: Bool,
        verifiedDownloadCount: Int
    ) -> Bool {
        libraryV2Enabled && isDisconnected && verifiedDownloadCount > 0
    }
}
