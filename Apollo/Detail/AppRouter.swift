//
// AppRouter.swift
// Apollo
//
// Created by 686udjie on 21/08/2026.
//

import Combine
import SwiftUI

/// Owns each tab's NavigationPath so overlays (e.g. the Big Player menu) can
/// push detail pages onto the regular tab navigation. Appending to a path is
/// plain state mutation, so it works even while views are transitioning —
/// unlike pub/sub events, which tabs can miss during player teardown.
@MainActor final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var homePath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var explorePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var selectedTabIndex = 0

    /// Last route opened from an overlay; ContentView listens to collapse the player.
    @Published private(set) var activeRoute: DetailRoute?

    @Published private(set) var playerExpandToken = 0

    var activePathDepth: Int {
        switch selectedTabIndex {
        case 2: libraryPath.count
        case 3: searchPath.count
        case 4: explorePath.count
        default: homePath.count
        }
    }

    func popActiveRoute() {
        guard activePathDepth > 0 else { return }
        switch selectedTabIndex {
        case 2: libraryPath.removeLast()
        case 3: searchPath.removeLast()
        case 4: explorePath.removeLast()
        default: homePath.removeLast()
        }
    }

    func expandPlayer() {
        playerExpandToken += 1
    }

    func open(_ route: DetailRoute) {
        switch selectedTabIndex {
        case 2: libraryPath.append(route)
        case 3: searchPath.append(route)
        case 4: explorePath.append(route)
        default: homePath.append(route)
        }
        activeRoute = route
    }
}
