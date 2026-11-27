import Foundation

enum PlaybackEventKind: String, Codable, Sendable {
    case play
    case pause
    case resume
    case skip
    case complete
    case save
}

/// Pure transition rules for playback events. One selection emits one `play`,
/// at most one pause/resume pair at a time, one terminal (skip or complete),
/// and one save per selection/session.
struct PlaybackEventPolicy {
    private(set) var currentSelectionID: String?
    private var terminalRecorded = false
    private var paused = false
    private var saved = Set<String>()

    mutating func begin(_ selectionID: String) -> Bool {
        guard !selectionID.isEmpty else { return false }
        if currentSelectionID == selectionID, !terminalRecorded {
            return false
        }
        currentSelectionID = selectionID
        terminalRecorded = false
        paused = false
        return true
    }

    mutating func pause(_ selectionID: String) -> Bool {
        guard isActive(selectionID), !paused else { return false }
        paused = true
        return true
    }

    mutating func resume(_ selectionID: String) -> Bool {
        guard isActive(selectionID), paused else { return false }
        paused = false
        return true
    }

    mutating func finish(_ selectionID: String, kind: PlaybackEventKind) -> Bool {
        guard kind == .skip || kind == .complete,
              isActive(selectionID) else { return false }
        terminalRecorded = true
        paused = false
        return true
    }

    mutating func save(_ selectionID: String) -> Bool {
        guard !selectionID.isEmpty, saved.insert(selectionID).inserted else { return false }
        return true
    }

    mutating func reset() {
        currentSelectionID = nil
        terminalRecorded = false
        paused = false
        saved.removeAll(keepingCapacity: true)
    }

    private func isActive(_ selectionID: String) -> Bool {
        currentSelectionID == selectionID && !terminalRecorded
    }
}
