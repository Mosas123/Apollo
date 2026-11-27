import SwiftUI

/// Local profile only. Apollo no longer signs in to YouTube; every library
/// action is stored on this device.
@MainActor
@Observable
final class AccountSheetState {
    static let shared = AccountSheetState()

    var accountName = "Apollo"
    var accountImageUrl: String?
    var accountChannelId: String?

    var isLoggedIn: Bool { false }

    private init() {}

    func restoreSession() async {}
    func fetchAccountInfo() async {}
    func signOut() {}
}
