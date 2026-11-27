//
//  View+App.swift
//  Apollo
//
//  Created by 686udjie on 13/09/2026.
//

import SwiftUI
import UIKit

extension View {
    /// Keeps the mini player's inline layout in sync with this scroll container:
    /// collapsing when scrolled down and restoring when back at the top.
    func miniPlayerTracksScroll(headerHidden: Binding<Bool>? = nil, headerOffset: Binding<CGFloat>? = nil) -> some View {
        modifier(MiniPlayerInlineOnScrollModifier(headerHidden: headerHidden, headerOffset: headerOffset))
    }

    /// Registers standard DetailRoute navigation
    func detailRouteDestinations() -> some View {
        self.navigationDestination(for: DetailRoute.self) { route in
            DetailRouteDestinationView(route: route)
        }
    }

    /// Presents a DetailRoute destination in a NavigationStack
    func detailRouteSheet(item: Binding<DetailRoute?>) -> some View {
        self.sheet(item: item) { route in
            NavigationStack {
                DetailRouteDestinationView(route: route)
                    // Sheets have their own stack and do not inherit the tab's
                    // typed destinations. Keep nested detail links navigable.
                    .detailRouteDestinations()
            }
        }
    }

    /// Standard sheet presentation: detents plus a visible drag indicator.
    func appSheetChrome(_ detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
    }
}

extension Color {
    /// Black or white, whichever reads better on top of this color. Used for
    /// text on accent-filled chips so dark accents stay legible.
    var readableForeground: Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6 ? .black : .white
    }
}
