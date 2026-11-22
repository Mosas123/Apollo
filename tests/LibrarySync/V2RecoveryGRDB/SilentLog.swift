import Foundation

/// Compile-time-only test shim. Production migrations are compiled unchanged
/// in this fixture, but diagnostic messages are discarded.
enum Log {
    static let db = SilentDatabaseLogger()
}
struct SilentDatabaseLogger: Sendable {
    func debug(_ message: String) {}
    func error(_ message: String) {}
}
