//
//  ApolloHomeDesign.swift
//  Apollo
//
//  The visual language for the Apollo Home surface: a living sky, a large
//  editorial hero, glass shelves and a media "orbit" switch.
//

import SwiftUI
import UIKit

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

        }
        .overlay {
            Circle()
                .fill(accent.opacity(isDark ? 0.34 : 0.16))
                .frame(width: 440, height: 440)
                .blur(radius: 130)
                .offset(x: drift ? 150 : -120, y: drift ? -230 : -140)
        }
        .overlay {
            Circle()
                .fill(Color(red: 0.42, green: 0.18, blue: 0.92).opacity(isDark ? 0.22 : 0.10))
                .frame(width: 520, height: 520)
                .blur(radius: 150)
                .offset(x: drift ? -190 : 160, y: drift ? 80 : 20)
        }
        .clipped()
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
                    .font(.system(size: 32, weight: .bold, design: .rounded))
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

/// Normalized key so an episode can find its show cover by artist/show name.
func podcastCoverKey(_ value: String) -> String {
    value
        .folding(options: .diacriticInsensitive, locale: .current)
        .lowercased()
        .replacingOccurrences(of: "podcast", with: "")
        .unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init)
        .joined()
}

private struct PodcastCoverEnvironmentKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}

extension EnvironmentValues {
    var podcastCovers: [String: String] {
        get { self[PodcastCoverEnvironmentKey.self] }
        set { self[PodcastCoverEnvironmentKey.self] = newValue }
    }
}

func podcastCoverURL(for item: YTItem, in covers: [String: String]) -> String? {
    if let videoId = item.videoId, let cover = covers["vid:\(videoId)"] {
        return cover
    }
    guard case .episode(let episode) = item else { return nil }

    var candidates = episode.artists.map(\.name)
    if let published = episode.publishDate { candidates.append(published) }

    for candidate in candidates {
        let key = podcastCoverKey(candidate)
        guard key.count >= 4 else { continue }
        if let cover = covers[key] { return cover }
        if let match = covers.first(where: {
            !$0.key.hasPrefix("vid:") && ($0.key.contains(key) || key.contains($0.key))
        }) {
            return match.value
        }
    }
    return nil
}

struct HomeArtwork: View {
    let item: YTItem

    @Environment(\.podcastCovers) private var podcastCovers

    private var resolvedURL: String? {
        if case .episode = item {
            return podcastCoverURL(for: item, in: podcastCovers) ?? item.thumbnailUrl
        }
        return item.thumbnailUrl
    }

    var body: some View {
        GeometryReader { geometry in
            if case .episode = item, let resolvedURL {
                AsyncImageView(url: resolvedURL)
            } else if let videoId = item.videoId, let image = NowPlaying.shared.artwork(for: videoId) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                AsyncImageView(url: resolvedURL)
            }
        }
    }
}

// MARK: - Hero

struct HomeHeroDisplay {
    var item: YTItem?
    var title: String
    var subtitle: String
    var kindLabel: String
    var badge: String?
    var artworkURL: String?
    var artworkImage: UIImage?
    var actionSymbol: String
}

extension YTItem {
    var homeHeroDisplay: HomeHeroDisplay {
        HomeHeroDisplay(
            item: self,
            title: title,
            subtitle: homeSubtitle,
            kindLabel: homeKindLabel,
            badge: homeBadge,
            artworkURL: nil,
            artworkImage: nil,
            actionSymbol: videoId == nil ? "chevron.right" : "play.fill"
        )
    }
}

struct HomeHeroCard: View {
    let display: HomeHeroDisplay
    let label: String
    let accent: Color
    let progress: Double?
    let onTap: () -> Void

    @ViewBuilder
    private var artwork: some View {
        if let image = display.artworkImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let url = display.artworkURL {
            AsyncImageView(url: url)
        } else if let item = display.item {
            HomeArtwork(item: item)
        } else {
            Color(.secondarySystemBackground)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
                .frame(maxWidth: .infinity)
                .frame(height: 320)
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

                    if let badge = display.badge {
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

                Text(display.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(display.subtitle)
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
                    Image(systemName: display.actionSymbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(.white, in: Circle())

                    Text(display.kindLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))

                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
        .frame(height: 320)
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
