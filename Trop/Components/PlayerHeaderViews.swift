//
//  PlayerHeaderViews.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import SwiftUI

/// Applies the user's Liquid Glass style to a player chip (iOS 26/27).
private struct PlayerGlassModifier: ViewModifier {
    @Environment(\.settingsStore) private var settings

    @ViewBuilder
    func body(content: Content) -> some View {
        switch settings.glassStyle {
        case .clear:
            content.glassEffect(.clear, in: Circle())
        case .regular:
            content.glassEffect(.regular, in: Circle())
        case .opaque:
            content.background(Color.black.opacity(0.4), in: Circle())
        }
    }
}

extension View {
    func playerGlass() -> some View { modifier(PlayerGlassModifier()) }
}

/// Title + artist marquee block shared by the FullPlayer, Queue and Lyrics
/// header rows.
struct PlayerTitleBlock: View {
    var title: String
    var artist: String
    var spacing: CGFloat = 2
    var titleFont: Font = .body.weight(.semibold)
    var titleHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            MarqueeText(
                text: title,
                font: titleFont,
                frameHeight: titleHeight
            )

            if !artist.isEmpty {
                Text(artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }
}

/// White heart toggle for player surfaces (FullPlayer, Queue).
struct PlayerLikeButton: View {
    var isLiked: Bool
    var activeColor: Color = .red
    var inactiveColor: Color = .white
    var fontSize: CGFloat = 17
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: fontSize, weight: .regular))
                .foregroundStyle(isLiked ? activeColor : inactiveColor)
                .frame(width: 36, height: 36)
                .playerGlass()
        }
    }
}

/// White ⋮ button for player surfaces. The options sheet stays owned by the caller.
struct PlayerOptionsButton: View {
    var color: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("⋮")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .playerGlass()
        }
        .accessibilityLabel("Song options")
    }
}
