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

struct TabHeaderMeasurementKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    func floatingTabHeader(scrollOffset: CGFloat, height: Binding<CGFloat>) -> some View {
        let progress = min(max(scrollOffset / max(height.wrappedValue, 1), 0), 1)
        return background {
            GeometryReader { geometry in
                Color.clear.preference(key: TabHeaderMeasurementKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(TabHeaderMeasurementKey.self) { if $0 > 0 { height.wrappedValue = $0 } }
        .background {
            Color(.systemBackground)
                .ignoresSafeArea(.container, edges: .top)
        }
        .offset(y: -min(max(scrollOffset, 0), height.wrappedValue))
        .opacity(1 - progress)
        .allowsHitTesting(progress < 0.95)
        .accessibilityHidden(progress >= 0.95)
    }
}
