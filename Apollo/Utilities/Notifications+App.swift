//
//  Notifications+App.swift
//  Apollo
//
//  Created by 686udjie on 13/09/2026.
//

import Foundation

extension Notification.Name {
    // durationDidUpdate comes from ApolloTube's DurationCache.
    static let personalizationDataUpdated = Notification.Name("personalizationDataUpdated")
    static let nowPlayingDidChange = Notification.Name("nowPlayingDidChange")
}
