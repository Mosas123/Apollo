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
    func floatingTabHeader(hidden: Bool, height: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: TabHeaderMeasurementKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(TabHeaderMeasurementKey.self) { if $0 > 0 { height.wrappedValue = $0 } }
        .background(.ultraThinMaterial)
        .offset(y: hidden ? -height.wrappedValue - 60 : 0)
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .accessibilityHidden(hidden)
    }
}
