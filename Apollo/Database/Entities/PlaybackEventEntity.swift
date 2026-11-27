import Foundation
import GRDB

struct PlaybackEventEntity: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: String
    var kind: String
    var selectionID: String
    var sessionID: String
    var videoID: String
    var catalogID: String?
    var title: String
    var artist: String
    var album: String?
    var source: String?
    var candidateSource: String?
    var position: Double
    var duration: Double
    var createdAt: Date

    static let databaseTableName = "playback_event"

    enum CodingKeys: String, CodingKey {
        case id, kind, title, artist, album, source, position, duration
        case selectionID = "selection_id"
        case sessionID = "session_id"
        case videoID = "video_id"
        case catalogID = "catalog_id"
        case candidateSource = "candidate_source"
        case createdAt = "created_at"
    }

    init(event: PlaybackEvent) {
        self.id = event.id.uuidString
        self.kind = event.kind.rawValue
        self.selectionID = event.selectionID
        self.sessionID = event.sessionID
        self.videoID = event.videoID
        self.catalogID = event.catalogID
        self.title = event.title
        self.artist = event.artist
        self.album = event.album
        self.source = event.source
        self.candidateSource = event.candidateSource
        self.position = event.position
        self.duration = event.duration
        self.createdAt = event.createdAt
    }
}
