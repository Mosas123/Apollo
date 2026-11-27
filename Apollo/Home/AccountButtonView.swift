//
//  AccountButtonView.swift
//  Apollo
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct AccountButtonView: View {
    var isLoggedIn: Bool
    var accountImageUrl: String?
    var size: CGFloat = 32
    var initial: String? = nil
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if isLoggedIn {
                AsyncImageView(url: accountImageUrl)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
            } else {
                fallback
            }
        }
        .buttonStyle(.plain)
    }

    private var fallback: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.60, green: 0.72, blue: 0.92),
                        Color(red: 0.42, green: 0.54, blue: 0.80)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text(initial ?? "A")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(.white)
            )
            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
    }
}
