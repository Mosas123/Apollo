import SwiftUI

/// Shared state for the player card presentation. The full player publishes the
/// downward drag distance so the mini player can coordinate its appearance;
/// ContentView owns the expanded flag.
@MainActor
@Observable
final class PlayerSheetState {
    static let shared = PlayerSheetState()

    var isExpanded = false
    var isCollapsing = false
    var hasExpandedArtwork = true
    /// Downward drag distance of the player card; 0 while fully expanded.
    var dragOffset: CGFloat = 0

    private init() {}
}
