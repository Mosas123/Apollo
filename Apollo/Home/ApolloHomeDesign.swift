//
//  ApolloHomeDesign.swift
//  Apollo
//
//  The visual language for the Apollo Home surface: a living sky, a large
//  editorial hero, glass shelves and a media "orbit" switch.
//

import SwiftUI

// MARK: - Content category language

extension ContentCategory {
    var homeAccent: Color {
        switch self {
        case .all: return Color(red: 0.55, green: 0.38, blue: 1.00)
        case .music: return Color(red: 0.55, green: 0.38, blue: 1.00)
        case .podcast: return Color(red: 1.00, green: 0.38, blue: 0.42)
        case .audiobook: return Color(red: 0.96, green: 0.62, blue: 0.20)
        }
    }

    var homeSymbol: String {
        switch self {
        case .all: return "sparkles"
        case .music: return "waveform"
        case .podcast: return "mic.fill"
        case .audiobook: return "book.closed.fill"
        }
    }

    var homeKicker: String {
        switch self {
        case .all: return "Your orbit"
        case .music: return "Music"
        case .podcast: return "Podcasts"
        case .audiobook: return "Audiobooks"
        }
    }
}

extension YTItem {
    var homeKindLabel: String {
        switch self {
        case .song: return "Song"
        case .album(let a): return a.isAudiobook ? "Audiobook" : "Album"
        case .artist: return "Artist"
        case .playlist: return "Playlist"
        case .podcast: return "Podcast"
        case .episode: return "Episode"
        }
    }

    var homeBadge: String? {
        switch self {
        case .album(let a): return a.isAudiobook ? "Audiobook" : nil
        case .podcast: return "Podcast"
        case .episode: return "Episode"
        default: return nil
        }
    }

    var homeSubtitle: String {
        switch self {
        case .song(let s):
            return s.artistNamesDisplay
        case .album(let a):
            return a.artists.map(\.name).joined(separator: ", ")
        case .artist:
            return "Artist"
        case .playlist(let p):
            return p.author ?? "Playlist"
        case .podcast(let p):
            return p.author ?? "Podcast"
        case .episode(let e):
            let names = e.artists.map(\.name).joined(separator: ", ")
            if !names.isEmpty { return names }
            return e.publishDate ?? "Episode"
        }
    }
}

// MARK: - Living sky

struct HomeSkyBackground: View {
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            (isDark
                ? Color(red: 0.02, green: 0.02, blue: 0.04)
                : Color(uiColor: .systemBackground))

            LinearGradient(
                colors: [
                    accent.opacity(isDark ? 0.38 : 0.16),
                    accent.opacity(isDark ? 0.10 : 0.04),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )

            Circle()
                .fill(accent.opacity(isDark ? 0.34 : 0.16))
                .frame(width: 440, height: 440)
                .blur(radius: 130)
                .offset(x: drift ? 150 : -120, y: drift ? -230 : -140)

            Circle()
                .fill(Color(red: 0.42, green: 0.18, blue: 0.92).opacity(isDark ? 0.22 : 0.10))
                .frame(width: 520, height: 520)
                .blur(radius: 150)
                .offset(x: drift ? -190 : 160, y: drift ? 80 : 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 16).repeatForever(autoreverses: true), value: drift)
        .onAppear { drift = true }
        .allowsHitTesting(false)
    }
}

// MARK: - Greeting

struct HomeGreetingHeader: View {
    let greeting: String
    let dateLine: String
    let accent: Color
    let accountIsLoggedIn: Bool
    let accountImageUrl: String?
    let accountInitial: String?
    let onAccount: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Text("A")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(accent, in: Circle())
                    Text("APOLLO")
                        .font(.caption2.weight(.black))
                        .tracking(2.6)
                        .foregroundStyle(.secondary)
                }

                Text(greeting)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(dateLine)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            AccountButtonView(
                isLoggedIn: accountIsLoggedIn,
                accountImageUrl: accountImageUrl,
                size: 44,
                initial: accountInitial,
                onTap: onAccount
            )
            .accessibilityLabel("Account")
        }
    }
}

// MARK: - Orbit switch

struct HomeOrbitSelector: View {
    @Binding var selection: ContentCategory
    let accent: Color
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ContentCategory.allCases) { category in
                let isSelected = selection == category
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        selection = category
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: category.homeSymbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text(LocalizedStringKey(category.title))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                                )
                                .matchedGeometryEffect(id: "orbit", in: namespace)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Section header

struct HomeSectionHeader: View {
    let kicker: String
    let title: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(kicker.uppercased())
                .font(.caption2.weight(.black))
                .tracking(1.9)
                .foregroundStyle(accent)
            Text(LocalizedStringKey(title))
                .font(.title3.weight(.bold))
        }
    }
}

// MARK: - Artwork

struct HomeArtwork: View {
    let item: YTItem

    var body: some View {
        GeometryReader { geometry in
            if let videoId = item.videoId, let image = NowPlaying.shared.artwork(for: videoId) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                AsyncImageView(url: item.thumbnailUrl)
            }
        }
    }
}

// MARK: - Hero

struct HomeHeroCard: View {
    let item: YTItem
    let label: String
    let subtitle: String
    let accent: Color
    let progress: Double?
    let onTap: () -> Void

    private var actionSymbol: String {
        item.videoId == nil ? "chevron.right" : "play.fill"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HomeArtwork(item: item)
                .frame(maxWidth: .infinity)
                .frame(height: 400)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.00), location: 0.30),
                    .init(color: .black.opacity(0.30), location: 0.55),
                    .init(color: .black.opacity(0.86), location: 0.82),
                    .init(color: .black.opacity(0.96), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(label.uppercased())
                        .font(.caption2.weight(.black))
                        .tracking(1.7)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.28), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))

                    if let badge = item.homeBadge {
                        Text(badge.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                Text(item.title)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)

                if let progress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.24))
                            Capsule()
                                .fill(.white)
                                .frame(width: geometry.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, 3)
                }

                HStack(spacing: 12) {
                    Image(systemName: actionSymbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 50, height: 50)
                        .background(.white, in: Circle())

                    Text(item.homeKindLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))

                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture(perform: onTap)
        .shadow(color: .black.opacity(0.35), radius: 26, y: 16)
    }
}

// MARK: - Continue card

struct HomeContinueCard: View {
    let item: YTItem
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            HomeArtwork(item: item)
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.homeKindLabel.uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(1.3)
                    .foregroundStyle(accent)
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(item.homeSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "play.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(accent)
        }
        .padding(12)
        .frame(width: 302, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Quick pick tile

struct HomeQuickTile: View {
    let item: YTItem
    let isPinned: Bool
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { HomeArtwork(item: item) }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                LinearGradient(
                    colors: [.clear, .black.opacity(0.30)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.94), in: Circle())
                    .padding(9)
            }
            .overlay(alignment: .topLeading) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(8)
                }
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(item.homeSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Shelf card

struct HomeShelfCard: View {
    let item: YTItem
    let accent: Color
    let onTap: () -> Void

    private var artworkShape: AnyShape {
        if case .artist = item {
            return AnyShape(Circle())
        }
        return AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeArtwork(item: item)
                .frame(width: 156, height: 156)
                .clipShape(artworkShape)
                .overlay {
                    artworkShape
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                }
                .overlay(alignment: .topLeading) {
                    if let badge = item.homeBadge {
                        Text(badge.uppercased())
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.0)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.36), in: Capsule())
                            .padding(8)
                    }
                }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(item.homeSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 156, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Surprise banner

struct HomeSurpriseBanner: View {
    let accent: Color
    let title: String
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("APOLLO'S PICK")
                    .font(.caption2.weight(.black))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.72))
                Text(LocalizedStringKey(title))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.16), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 0.5))
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [accent, accent.opacity(0.58)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onTap)
    }
}
