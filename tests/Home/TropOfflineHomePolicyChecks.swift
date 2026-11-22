import Foundation

@main
enum TropOfflineHomePolicyChecks {
    static func main() {
        let disconnected = URLError(.notConnectedToInternet)
        let interrupted = URLError(.networkConnectionLost)
        let timeout = URLError(.timedOut)

        precondition(TropOfflineHomePolicy.isDisconnected(disconnected))
        precondition(TropOfflineHomePolicy.isDisconnected(interrupted))
        precondition(!TropOfflineHomePolicy.isDisconnected(timeout))

        precondition(TropOfflineHomePolicy.showDownloads(
            libraryV2Enabled: true, isDisconnected: true, verifiedDownloadCount: 2
        ))
        precondition(!TropOfflineHomePolicy.showDownloads(
            libraryV2Enabled: true, isDisconnected: true, verifiedDownloadCount: 0
        ))
        precondition(!TropOfflineHomePolicy.showDownloads(
            libraryV2Enabled: true, isDisconnected: false, verifiedDownloadCount: 2
        ))
        precondition(!TropOfflineHomePolicy.showDownloads(
            libraryV2Enabled: false, isDisconnected: true, verifiedDownloadCount: 2
        ))

        // A metadata-only saved radio, playlist or favorite cannot increase
        // the verified *download* count. The caller supplies the reconciled
        // DownloadManager.tracks count, not V2 library item counts.
        print("Trop offline Home downloads-only policy passed")
    }
}
