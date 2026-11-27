//
//  DurationResolver.swift
//  Apollo
//
//  Created by 686udjie on 2/07/2026.
//

import Foundation
import Observation

/// Resolves unknown track durations via the shared `InnerTubeClient`,
/// shared by every song row and grid cell.
@MainActor
@Observable
final class DurationResolver {
    var resolved = 0

    func effectiveDuration(known: Int) -> Int {
        known > 0 ? known : resolved
    }

    func resolve(videoId: String, knownDuration: Int) async {
        guard knownDuration <= 0, MusicPlaybackIdentity.isYouTube(videoId) else { return }
        if let duration = await InnerTubeClient.apolloShared.resolveDuration(videoId: videoId) {
            resolved = duration
        }
    }

    func handleUpdate(_ notification: Notification, videoId: String?) {
        guard let videoId else { return }
        let info = notification.userInfo
        let matches: Bool
        if let single = info?["videoId"] as? String {
            matches = single == videoId
        } else if let many = info?["videoIds"] as? [String] {
            matches = many.contains(videoId)
        } else {
            matches = false
        }
        guard matches else { return }
        resolved = DurationCache.get(videoId) ?? 0
    }
}
