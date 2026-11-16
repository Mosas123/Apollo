import Foundation

/// A `Sendable` wrapper for raw InnerTube JSON responses so they can cross
/// actor-isolation boundaries under Swift 6 strict concurrency.
public struct TubeJSON: @unchecked Sendable {
    public let value: [String: Any]
    public init(_ value: [String: Any]) { self.value = value }
}
