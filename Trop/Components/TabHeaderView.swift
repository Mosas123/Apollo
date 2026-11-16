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
    var onHistory: () -> Void
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
