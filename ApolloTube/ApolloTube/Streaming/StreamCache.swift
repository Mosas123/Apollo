//
//  StreamCache.swift
//  ApolloTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Stream URLs with TTL expiry.
public actor StreamCache {
    public static let shared = StreamCache()

    private var cache: [String: Entry] = [:]

    private struct Entry {
        let result: PlaybackResult
        let expiresAt: Date
    }

    public init() {}

    public func get(videoId: String) -> PlaybackResult? {
        guard let entry = cache[videoId], entry.expiresAt > Date() else {
            cache.removeValue(forKey: videoId)
            return nil
        }
        return entry.result
    }

    public func getExpired(videoId: String) -> PlaybackResult? {
        cache[videoId]?.result
    }

    public func set(videoId: String, result: PlaybackResult) {
        // Drop already-expired entries and cap the cache so tracks that are
        // never revisited don't stay in memory forever.
        let now = Date()
        cache = cache.filter { $0.value.expiresAt > now }
        if cache.count >= 200 {
            let keep = cache.sorted { $0.value.expiresAt > $1.value.expiresAt }.prefix(150)
            cache = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        let reported = max(result.expiresInSeconds, 0)
        let ttl = reported > 60 ? max(reported - 60, 60) : 5 * 60
        let entry = Entry(result: result, expiresAt: Date().addingTimeInterval(TimeInterval(ttl)))
        cache[videoId] = entry
        ApolloTubeLog.debug("Cached videoId=\(videoId) expires in \(ttl)s")
    }

    public func remove(videoId: String) {
        cache.removeValue(forKey: videoId)
    }

    public func clear() {
        cache.removeAll()
    }
}
