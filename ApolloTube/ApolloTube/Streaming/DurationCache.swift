//
//  DurationCache.swift
//  ApolloTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

public extension Notification.Name {
    /// Posted on the main queue whenever a duration is stored. The payload
    /// carries `videoIds` (an array) and is coalesced per run-loop batch so a
    /// burst of lookups doesn't fire hundreds of separate notifications.
    static let durationDidUpdate = Notification.Name("ApolloTubeDurationDidUpdate")
}

/// Thread-safe video durations with in-flight marking and LRU eviction.
public enum DurationCache: Sendable {
    nonisolated(unsafe) private static var cache: [String: Int] = [:]
    nonisolated(unsafe) private static var recency: [String: Int] = [:]
    nonisolated(unsafe) private static var clock = 0
    nonisolated(unsafe) private static var pending: Set<String> = []
    nonisolated(unsafe) private static var dirtyIds: Set<String> = []
    nonisolated(unsafe) private static var notificationScheduled = false
    private static let lock = NSLock()

    public static func isPending(_ videoId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pending.contains(videoId)
    }

    public static func get(_ videoId: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard let duration = cache[videoId] else { return nil }
        clock &+= 1
        recency[videoId] = clock
        return duration
    }

    public static func set(_ videoId: String, _ duration: Int) {
        lock.lock()
        clock &+= 1
        cache[videoId] = duration
        recency[videoId] = clock
        pending.remove(videoId)
        if cache.count > 4000 { evictLocked() }
        dirtyIds.insert(videoId)
        let shouldSchedule = !notificationScheduled
        if shouldSchedule { notificationScheduled = true }
        lock.unlock()

        if shouldSchedule {
            DispatchQueue.main.async { flushNotifications() }
        }
    }

    public static func markPending(_ videoId: String) {
        lock.lock(); defer { lock.unlock() }
        pending.insert(videoId)
    }

    public static func clearPending(_ videoId: String) {
        lock.lock(); defer { lock.unlock() }
        pending.remove(videoId)
    }

    /// Evicts the least-recently-used quarter. Must be called with `lock` held.
    private static func evictLocked() {
        let victims = recency.sorted { $0.value < $1.value }.prefix(1000)
        for (key, _) in victims {
            cache.removeValue(forKey: key)
            recency.removeValue(forKey: key)
        }
    }

    private static func flushNotifications() {
        lock.lock()
        let ids = Array(dirtyIds)
        dirtyIds.removeAll(keepingCapacity: true)
        notificationScheduled = false
        lock.unlock()
        guard !ids.isEmpty else { return }
        NotificationCenter.default.post(
            name: .durationDidUpdate,
            object: nil,
            userInfo: ["videoIds": ids]
        )
    }
}
