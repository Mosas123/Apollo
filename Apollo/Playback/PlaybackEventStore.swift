import Foundation
import GRDB

/// Buffered writer for the append-only playback_event table. It never blocks
/// the player: inserts happen on a small actor with a 5 s / 20 event flush.
actor PlaybackEventStore {
    static let shared = PlaybackEventStore()

    private var buffer: [PlaybackEvent] = []
    private var flushTask: Task<Void, Never>?
    private let retentionDays = 90

    func enqueue(_ event: PlaybackEvent) {
        buffer.append(event)
        if buffer.count >= 20 {
            Task { await self.flush() }
        } else if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                await self?.flush()
            }
        }
    }

    func flush() async {
        flushTask?.cancel()
        flushTask = nil
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)

        do {
            try await DatabaseService.shared.write { db in
                for event in batch {
                    try PlaybackEventEntity(event: event).insert(db)
                }
                try db.execute(
                    sql: "DELETE FROM playback_event WHERE created_at < ?",
                    arguments: [cutoff]
                )
            }
        } catch {
            Log.db.error("Could not persist \(batch.count) playback events: \(error)")
        }
    }

    func recent(limit: Int = 100) async -> [PlaybackEventEntity] {
        await flush()
        return (try? await DatabaseService.shared.fetchAll(
            PlaybackEventEntity.self,
            sql: "SELECT * FROM playback_event ORDER BY created_at DESC LIMIT ?",
            arguments: [max(1, limit)]
        )) ?? []
    }
}

@MainActor
final class PlaybackEventRecorder {
    static let shared = PlaybackEventRecorder()

    private var policy = PlaybackEventPolicy()
    private var sessionID = UUID().uuidString
    private(set) var current: SongItem?
    private var currentPosition: TimeInterval = 0

    func startSession() {
        sessionID = UUID().uuidString
        policy.reset()
        current = nil
        currentPosition = 0
    }

    func begin(_ song: SongItem, position: TimeInterval = 0) {
        let id = selectionID(for: song)
        guard policy.begin(id) else {
            current = song
            currentPosition = position
            return
        }
        current = song
        currentPosition = position
        emit(.play, song: song, position: position)
    }

    func skipCurrent(position: TimeInterval? = nil) {
        guard let song = current else { return }
        let offset = position ?? currentPosition
        currentPosition = offset
        guard policy.finish(selectionID(for: song), kind: .skip) else { return }
        emit(.skip, song: song, position: offset)
    }

    func completeCurrent(duration: TimeInterval) {
        guard let song = current else { return }
        currentPosition = duration
        guard policy.finish(selectionID(for: song), kind: .complete) else { return }
        emit(.complete, song: song, position: duration)
    }

    func recordPause(_ paused: Bool, position: TimeInterval? = nil) {
        guard let song = current else { return }
        if let position { currentPosition = position }
        let id = selectionID(for: song)
        if paused {
            guard policy.pause(id) else { return }
            emit(.pause, song: song, position: currentPosition)
        } else {
            guard policy.resume(id) else { return }
            emit(.resume, song: song, position: currentPosition)
        }
    }

    func recordSave(_ song: SongItem, saved: Bool) {
        guard saved, policy.save(selectionID(for: song)) else { return }
        emit(.save, song: song, position: currentPosition)
    }

    private func emit(_ kind: PlaybackEventKind, song: SongItem, position: TimeInterval) {
        let event = PlaybackEvent(
            id: UUID(),
            kind: kind,
            selectionID: selectionID(for: song),
            sessionID: sessionID,
            videoID: song.videoId,
            catalogID: song.catalogID,
            title: song.title,
            artist: song.artists.map(\.name).joined(separator: ", "),
            album: song.album,
            source: source(of: song),
            candidateSource: song.stationReason,
            position: max(0, position),
            duration: max(0, TimeInterval(song.duration)),
            createdAt: Date()
        )
        Task { await PlaybackEventStore.shared.enqueue(event) }
    }

    private func selectionID(for song: SongItem) -> String {
        song.catalogID ?? song.videoId
    }

    private func source(of song: SongItem) -> String? {
        if let catalogID = song.catalogID {
            return catalogID.split(separator: ":").first.map(String.init)
        }
        if song.videoId.hasPrefix("podcast:") { return "podcast" }
        return nil
    }
}
