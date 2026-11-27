import Foundation

/// Append-only listening event. The raw stream stays cheap; aggregation can
/// happen later without losing skip/complete/pause nuance.
struct PlaybackEvent: Sendable {
    let id: UUID
    let kind: PlaybackEventKind
    let selectionID: String
    let sessionID: String
    let videoID: String
    let catalogID: String?
    let title: String
    let artist: String
    let album: String?
    let source: String?
    let candidateSource: String?
    let position: TimeInterval
    let duration: TimeInterval
    let createdAt: Date
}
