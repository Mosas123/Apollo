//
//  PlaybackControlsView.swift
//  Apollo
//
//  Created by 686udjie on 2/07/2026.
//

import SwiftUI

/// Shuffle / play / more circular buttons shared by every detail header.
/// Canonicalizes on the PlaylistHeaderView styling (48/64pt, grouped
/// background, accent glow shadow).
struct PlaybackControlsView: View {
    var accent: Color = .accentColor
    var albumStyle: Bool = false
    var showsShuffle: Bool = true
    var showsMore: Bool = false
    var onPlay: () -> Void
    var onShuffle: () -> Void = {}
    var onMore: () -> Void = {}

    var body: some View {
        HStack(spacing: 16) {
            if showsShuffle {
                Button(action: onShuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(sideButtonColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shuffle")
            }

            Button(action: onPlay) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Play")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .frame(maxWidth: albumStyle ? 180 : .infinity)
                .frame(height: 48)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play all")

            if showsMore {
                Button(action: onMore) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(sideButtonColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    private var sideButtonColor: Color {
        albumStyle ? Color.primary.opacity(0.14) : Color(.secondarySystemGroupedBackground)
    }
}
