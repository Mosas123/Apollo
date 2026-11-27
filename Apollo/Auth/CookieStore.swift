import Foundation

/// YouTube login is gone. The app never persists or exposes YouTube cookies;
/// this stub keeps anonymous audio requests and read-only services compiling.
actor CookieStore {
    func cookies() async -> [String: String] { [:] }
    func sapisid() async -> String? { nil }
    func visitorData() async -> String? { nil }
    func dataSyncId() async -> String? { nil }
    func isLoggedIn() async -> Bool { false }
    func save(
        cookies: [String: String],
        sapisid: String?,
        visitorData: String?,
        dataSyncId: String? = nil
    ) {}
    func clear() {}
}
