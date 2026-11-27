import Foundation

/// The catalogue side of the app. Audio resolution is a separate concern so
/// YouTube can be demoted to an audio provider without touching this layer.
protocol CatalogSearching: Sendable {
    var source: CatalogSource { get }
    func search(_ query: String, limit: Int) async throws -> CatalogSearchResults
}
