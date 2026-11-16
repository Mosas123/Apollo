//
//  ContentView.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Combine
import SwiftUI

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var nowPlaying = NowPlaying.shared
    @State private var selectedTab = SettingsStore.shared.defaultTab
    @State private var isExpanded = false
    @State private var scrollState = MiniPlayerScrollState()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "music.note.house.fill", value: 0) {
                HomeScreenView()
            }

            if settings.showRadioTab {
                Tab("Radio", systemImage: "dot.radiowaves.left.and.right", value: 1) {
                    RadioView()
                }
            }

            Tab("Library", systemImage: "music.note.square.stack", value: 2) {
                LibraryView()
            }

            if settings.showExploreTab {
                Tab("Explore", systemImage: "flame", value: 4) {
                    ExploreView()
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: 3, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory(isEnabled: nowPlaying.isBarPresented) {
                MiniPlayerBarView(onExpand: {
                    // Dismiss the keyboard before expanding the player so the reveal is visible on the first tap.
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                    withAnimation(.smooth(duration: 0.3)) {
                        isExpanded = true
                    }
                })
            }
            .background {
                backgroundLayer
            }
            .overlay {
                if isExpanded {
                    FullPlayerView(onCollapse: {
                        withAnimation(.smooth(duration: 0.3)) {
                            isExpanded = false
                        }
                    })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .environment(scrollState)
        .onAppear {
            if selectedTab == 1 && !settings.showRadioTab { selectedTab = 0 }
            if selectedTab == 4 && !settings.showExploreTab { selectedTab = 0 }
            AppRouter.shared.selectedTabIndex = selectedTab
        }
        .onChange(of: settings.showRadioTab) { _, shown in
            if !shown, selectedTab == 1 { selectedTab = 0 }
        }
        .onChange(of: settings.showExploreTab) { _, shown in
            if !shown, selectedTab == 4 { selectedTab = 0 }
        }
        .onChange(of: selectedTab) { _, newValue in
            AppRouter.shared.selectedTabIndex = newValue
        }
        .onReceive(AppRouter.shared.$activeRoute) { route in
            // A detail page was opened from an overlay: collapse the player so
            // the pushed page is visible underneath.
            if route != nil {
                withAnimation(.smooth(duration: 0.3)) {
                    isExpanded = false
                }
            }
        }
        .onReceive(AppRouter.shared.$playerExpandToken.dropFirst()) { _ in
            withAnimation(.smooth(duration: 0.3)) {
                isExpanded = true
            }
        }
        .simultaneousGesture(backSwipeGesture)
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard !isExpanded,
                      value.startLocation.x <= 28,
                      isHorizontal,
                      value.translation.width > 80 else { return }

                let router = AppRouter.shared
                let depth = router.activePathDepth
                guard depth > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard !isExpanded, router.activePathDepth == depth else { return }
                    router.popActiveRoute()
                }
            }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if settings.playerBackgroundStyle == .solid {
            Color.black.ignoresSafeArea()
        } else if let accent = nowPlaying.accentColor {
            accent
                .opacity(0.06)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: nowPlaying.accentColor)
        }
    }
}

#Preview {
    ContentView()
}
