//
//  TabHeaderView.swift
//  Trop
//
//  Created by 686udjie on 18/08/2026.
//

import SwiftUI

/// Shared large-title header with history and account buttons,
/// used by the Home and Library tabs.
struct TabHeaderView: View {
    let title: String
    var accountIsLoggedIn: Bool = false
    var accountImageUrl: String?
    var onAccount: () -> Void
    var accountInitial: String? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(LocalizedStringKey(title))
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            AccountButtonView(
                isLoggedIn: accountIsLoggedIn,
                accountImageUrl: accountImageUrl,
                size: 44,
                initial: accountInitial,
                onTap: onAccount
            )
            .accessibilityLabel("Account")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Hides a tab title while moving down through content and restores it on
/// scroll back. Keep the search field outside this collapsible header.
struct TabHeaderScrollModifier: ViewModifier {
    @Binding var isHidden: Bool

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { oldOffset, newOffset in
            let shouldHide: Bool
            if newOffset <= 20 {
                shouldHide = false
            } else if newOffset > oldOffset + 1 {
                shouldHide = true
            } else if newOffset < oldOffset - 1 {
                shouldHide = false
            } else {
                return
            }
            guard shouldHide != isHidden else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isHidden = shouldHide }
        }
    }
}

extension View {
    func tabHeaderTracksScroll(isHidden: Binding<Bool>) -> some View {
        modifier(TabHeaderScrollModifier(isHidden: isHidden))
    }

    func collapsibleTabHeader(isHidden: Bool) -> some View {
        self
            .frame(height: isHidden ? 0 : nil, alignment: .top)
            .clipped()
            .opacity(isHidden ? 0 : 1)
            .accessibilityHidden(isHidden)
            .allowsHitTesting(!isHidden)
    }
}
