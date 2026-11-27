//
// DatabaseMigrations.swift
// Apollo
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

enum DatabaseMigrations {
    /// Wraps a migration body with start/complete debug logs.
    static func logged(_ name: String, _ block: @escaping @Sendable (Database) throws -> Void) -> @Sendable (Database) throws -> Void {
        { db in
            Log.db.debug("Running \(name) migration")
            try block(db)
            Log.db.debug("\(name) migration complete")
        }
    }

    /// The canonical downloaded_track DDL, shared by v5 (fresh create) and
    /// v7 (rebuild target).
    static func createDownloadedTrackTable(_ db: Database, named name: String = "downloaded_track") throws {
        try db.create(table: name) { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("artist", .text).notNull()
            t.column("duration", .integer).notNull()
            t.column("thumbnail_url", .text)
            t.column("local_path", .text).notNull()
            t.column("downloaded_at", .text).notNull()
        }
    }

    static let v1: @Sendable (Database) throws -> Void = { db in
        try db.create(table: "song") { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("duration", .integer).notNull()
            t.column("thumbnail_url", .text)
            t.column("liked", .integer).notNull().defaults(to: false)
            t.column("total_play_time", .integer).notNull().defaults(to: 0)
            t.column("in_library", .text)
            t.column("library_add_token", .text).notNull().defaults(to: "")
            t.column("library_remove_token", .text).notNull().defaults(to: "")
            t.column("is_episode", .integer).notNull().defaults(to: false)
            t.column("is_uploaded", .integer).notNull().defaults(to: false)
            t.column("is_video", .integer).notNull().defaults(to: false)
            t.column("create_date", .text).notNull()
            t.column("modify_date", .text).notNull()
        }

        try db.create(table: "artist") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("thumbnail_url", .text)
            t.column("bookmarked_at", .text)
            t.column("is_podcast_channel", .integer).notNull().defaults(to: false)
        }

        try db.create(table: "album") { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("playlist_id", .text)
            t.column("thumbnail_url", .text)
            t.column("song_count", .integer).notNull().defaults(to: 0)
            t.column("duration", .integer).notNull().defaults(to: 0)
            t.column("bookmarked_at", .text)
        }

        try db.create(table: "playlist") { t in
            t.column("id", .text).primaryKey()
            t.column("browse_id", .text)
            t.column("name", .text).notNull()
            t.column("is_editable", .integer).notNull().defaults(to: false)
            t.column("bookmarked_at", .text)
            t.column("remote_song_count", .integer)
        }

        try db.create(table: "playlist_song_map") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("playlist_id", .text).notNull()
            t.column("song_id", .text).notNull()
            t.column("position", .integer).notNull()
            t.column("set_video_id", .text)
            t.uniqueKey(["playlist_id", "song_id"])
        }

        try db.create(table: "event") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("song_id", .text).notNull()
            t.column("timestamp", .text).notNull()
            t.column("play_time", .integer).notNull()
            t.uniqueKey(["song_id", "timestamp"])
        }

        try db.create(table: "play_count") { t in
            t.column("song_id", .text).notNull()
            t.column("year", .integer).notNull()
            t.column("month", .integer).notNull()
            t.column("count", .integer).notNull().defaults(to: 0)
            t.primaryKey(["song_id", "year", "month"])
        }

        try db.create(table: "format") { t in
            t.column("id", .text).primaryKey()
            t.column("itag", .integer).notNull()
            t.column("mime_type", .text).notNull()
            t.column("codecs", .text).notNull()
            t.column("bitrate", .integer).notNull()
            t.column("sample_rate", .integer).notNull()
            t.column("content_length", .integer).notNull()
            t.column("loudness_db", .double)
            t.column("perceptual_loudness_db", .double)
            t.column("playback_url", .text)
        }
    }

    static let v2: @Sendable (Database) throws -> Void = { db in
        try db.alter(table: "song") { t in
            t.add(column: "artist_name", .text)
            t.add(column: "album_name", .text)
        }
    }

    static let v3: @Sendable (Database) throws -> Void = logged("v3") { db in
        try db.alter(table: "artist") { t in
            t.add(column: "channel_id", .text)
        }

        try db.alter(table: "album") { t in
            t.add(column: "is_uploaded", .integer).notNull().defaults(to: false)
        }

        try db.alter(table: "playlist") { t in
            t.add(column: "is_auto_sync", .integer).notNull().defaults(to: false)
        }

        try db.create(table: "episode") { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("duration", .integer).notNull()
            t.column("thumbnail_url", .text)
            t.column("podcast_id", .text)
            t.column("podcast_name", .text)
            t.column("is_played", .integer).notNull().defaults(to: false)
            t.column("saved_at", .text)
        }

        try db.create(table: "podcast") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("thumbnail_url", .text)
            t.column("subscribed_at", .text)
        }

        try db.create(table: "podcast_episode_map") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("podcast_id", .text).notNull()
            t.column("episode_id", .text).notNull()
            t.column("position", .integer).notNull()
            t.uniqueKey(["podcast_id", "episode_id"])
        }
    }

    static let v4: @Sendable (Database) throws -> Void = logged("v4") { db in
        try db.alter(table: "playlist") { t in
            t.add(column: "thumbnail_url", .text)
        }
    }

    static let v5: @Sendable (Database) throws -> Void = logged("v5") { db in
        if try db.tableExists("downloaded_track") == false {
            try createDownloadedTrackTable(db)
        } else if try db.columns(in: "downloaded_track").contains(where: { $0.name == "artist" }) == false {
            // Table existed from an earlier schema without the artist column.
            try db.alter(table: "downloaded_track") { t in
                t.add(column: "artist", .text).notNull().defaults(to: "")
            }
        }
    }

    static let v6: @Sendable (Database) throws -> Void = logged("v6") { db in
        // Earlier schemas may have created downloaded_track with fewer columns
        // than DownloadedTrackEntity expects. Add any missing columns so inserts
        // from the app succeed on existing databases.
        if try db.tableExists("downloaded_track") {
            let existing = try db.columns(in: "downloaded_track").map(\.name)
            struct RequiredColumn {
                let name: String
                let type: Database.ColumnType
                let notNull: Bool
            }
            let required: [RequiredColumn] = [
                RequiredColumn(name: "artist", type: .text, notNull: true),
                RequiredColumn(name: "thumbnail_url", type: .text, notNull: false),
                RequiredColumn(name: "local_path", type: .text, notNull: true),
                RequiredColumn(name: "downloaded_at", type: .text, notNull: true),
                RequiredColumn(name: "duration", type: .integer, notNull: true),
                RequiredColumn(name: "title", type: .text, notNull: true)
            ]
            for col in required where !existing.contains(col.name) {
                try db.alter(table: "downloaded_track") { t in
                    let added = t.add(column: col.name, col.type)
                    if col.notNull {
                        added.notNull().defaults(to: "")
                    }
                }
            }
        }
    }

    static let v7: @Sendable (Database) throws -> Void = logged("v7") { db in
        // The existing downloaded_track table may have been created by an older
        // schema (e.g. with a file_size column) that doesn't match
        // DownloadedTrackEntity. Rebuild it to exactly match the entity,
        // preserving any rows we can carry over by id.
        if try db.tableExists("downloaded_track") {
            try createDownloadedTrackTable(db, named: "downloaded_track_new")
            // Carry over rows that have the columns we need (id + local_path).
            if try db.columns(in: "downloaded_track").contains(where: { $0.name == "local_path" }) {
                // Use a GRDB-compatible timestamp for any row missing downloaded_at,
                // so GRDB can decode it back into a Date on fetch.
                let fallback = DateFormatter()
                fallback.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
                fallback.locale = Locale(identifier: "en_US_POSIX")
                fallback.timeZone = TimeZone(secondsFromGMT: 0)
                let fallbackDate = fallback.string(from: Date())
                try db.execute(
                    sql: """
                        INSERT INTO downloaded_track_new (id, title, artist, duration, thumbnail_url, local_path, downloaded_at)
                        SELECT id,
                               COALESCE(title, ''),
                               COALESCE(artist, ''),
                               COALESCE(duration, 0),
                               thumbnail_url,
                               local_path,
                               COALESCE(NULLIF(downloaded_at, ''), ?)
                        FROM downloaded_track
                        WHERE local_path IS NOT NULL
                    """,
                    arguments: [fallbackDate]
                )
            }
            try db.drop(table: "downloaded_track")
            try db.rename(table: "downloaded_track_new", to: "downloaded_track")
        }
    }

    static let v8: @Sendable (Database) throws -> Void = logged("v8") { db in
        // Songs pinned to the homepage Speed Dial.
        if try !db.tableExists("speed_dial") {
            try db.create(table: "speed_dial") { t in
                t.column("video_id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("album", .text)
                t.column("thumbnail_url", .text)
                t.column("duration", .integer).notNull().defaults(to: 0)
                t.column("pinned_at", .datetime).notNull()
            }
        }
    }

    static let v9: @Sendable (Database) throws -> Void = logged("v9") { db in
        // Secondary indexes for hot reads: liked/library filters, play-time and
        // date ordering, event recency lookups, playlist membership, and
        // bookmark ordering. Full-table scans dominated these otherwise.
        let statements = [
            "CREATE INDEX IF NOT EXISTS idx_song_liked ON song(liked)",
            "CREATE INDEX IF NOT EXISTS idx_song_total_play_time ON song(total_play_time)",
            "CREATE INDEX IF NOT EXISTS idx_song_create_date ON song(create_date)",
            "CREATE INDEX IF NOT EXISTS idx_event_song_id ON event(song_id)",
            "CREATE INDEX IF NOT EXISTS idx_event_timestamp ON event(timestamp)",
            "CREATE INDEX IF NOT EXISTS idx_playlist_song_map_playlist ON playlist_song_map(playlist_id)",
            "CREATE INDEX IF NOT EXISTS idx_playlist_song_map_song ON playlist_song_map(song_id)",
            "CREATE INDEX IF NOT EXISTS idx_artist_bookmarked_at ON artist(bookmarked_at)",
            "CREATE INDEX IF NOT EXISTS idx_album_bookmarked_at ON album(bookmarked_at)",
            "CREATE INDEX IF NOT EXISTS idx_playlist_bookmarked_at ON playlist(bookmarked_at)"
        ]
        for sql in statements {
            try db.execute(sql: sql)
        }
    }

    static let v10: @Sendable (Database) throws -> Void = logged("v10") { db in
        // Canonical catalogue identity shared across providers.
        if try !db.tableExists("catalog_identity") {
            try db.create(table: "catalog_identity") { t in
                t.column("id", .text).primaryKey()
                t.column("source", .text).notNull()
                t.column("title", .text).notNull()
                t.column("artist_names", .text)
                t.column("album_title", .text)
                t.column("duration_ms", .integer).notNull().defaults(to: 0)
                t.column("isrc", .text)
                t.column("mbid", .text)
                t.column("artwork_url", .text)
                t.column("genre", .text)
                t.column("release_date", .text)
                t.column("spotify_id", .text)
                t.column("youtube_id", .text)
                t.column("updated_at", .text).notNull()
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_catalog_identity_isrc ON catalog_identity(isrc)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_catalog_identity_mbid ON catalog_identity(mbid)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_catalog_identity_spotify ON catalog_identity(spotify_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_catalog_identity_youtube ON catalog_identity(youtube_id)")
        }
    }

    static let v11: @Sendable (Database) throws -> Void = logged("v11") { db in
        // Append-only listening stream for radio affinity and bandit learning.
        if try !db.tableExists("playback_event") {
            try db.create(table: "playback_event") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("selection_id", .text).notNull()
                t.column("session_id", .text).notNull()
                t.column("video_id", .text).notNull()
                t.column("catalog_id", .text)
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("album", .text)
                t.column("source", .text)
                t.column("candidate_source", .text)
                t.column("position", .double).notNull().defaults(to: 0)
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_playback_event_created ON playback_event(created_at)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_playback_event_session ON playback_event(session_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_playback_event_selection ON playback_event(selection_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_playback_event_kind ON playback_event(kind)")
        }
    }
}
