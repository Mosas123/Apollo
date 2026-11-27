//
//  AsyncImageView.swift
//  Apollo
//
//  Created by 686udjie on 01/07/2026.
//

import Nuke
import SwiftUI

/// Sticky in-memory artwork cache that survives view re-creation (LazyVStack
/// recycling), independently of Nuke's evictable cache. A row that already
/// showed a cover must never flash — or get stuck on — the placeholder when it
/// scrolls back in or the list re-lays out.
private final class StickyArtworkCache: @unchecked Sendable {
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 500
        // Also cap by bytes: count alone lets 500 full-size bitmaps pile up.
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

private enum StickyArtwork {
    static let cache = StickyArtworkCache()

    static func image(for key: String) -> UIImage? {
        cache.image(for: key)
    }

    static func store(_ image: UIImage, for key: String) {
        cache.store(image, for: key)
    }
}

struct AsyncImageView: View {
    let url: String?
    var contentMode: ContentMode = .fill
    /// Called with the image once it is shown (sticky hit or fresh load), so
    /// callers can derive colors without downloading the artwork again.
    var onImageLoaded: ((UIImage) -> Void)? = nil
    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?
    @State private var loadedKey: String?

    /// Empties the sticky artwork cache (used by the memory-warning handler).
    static func clearArtworkCache() {
        StickyArtwork.cache.clear()
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                        .clipped()
                } else {
                    placeholderView
                }
            }
            .task(id: url) {
                await loadImage(targetSize: geometry.size)
            }
        }
    }

    private func loadImage(targetSize: CGSize) async {
        guard let urlString = url else {
            loadedImage = nil
            loadedKey = nil
            return
        }
        let scale = displayScale
        // Prevent zero-size layout passes from causing degenerate image cache requests.
        let minPixels: CGFloat = 120 * scale
        let displaySize = CGSize(
            width: max(targetSize.width * scale, minPixels),
            height: max(targetSize.height * scale, minPixels)
        )
        // Request the ladder rung covering this surface (BitChord-style),
        // so rows, cards and headers each share one cache entry.
        let rung = ArtworkURLs.rung(for: max(displaySize.width, displaySize.height))
        let normalized = normalizeThumbnailURL(urlString, pixels: rung)

        // A recycled row must not keep a previous song's cover while the new one
        // loads; a re-created row starts empty and is refilled from the sticky
        // cache below, so a previously shown cover never flickers back.
        if loadedKey != normalized {
            loadedImage = nil
            loadedKey = nil
        }
        if loadedImage == nil, let sticky = StickyArtwork.image(for: normalized) {
            loadedImage = sticky
            loadedKey = normalized
            onImageLoaded?(sticky)
        }

        guard let imageURL = URL(string: normalized) else { return }
        let request: ImageRequest = contentMode == .fill
            ? ImageRequest(
                url: imageURL,
                processors: [.resize(size: displaySize, unit: .pixels, contentMode: .aspectFill)]
            )
            : ImageRequest(url: imageURL)

        if let image = try? await ImagePipeline.shared.image(for: request) {
            guard !Task.isCancelled else { return }
            StickyArtwork.store(image, for: normalized)
            loadedKey = normalized
            withAnimation(.easeInOut(duration: 0.2)) {
                loadedImage = image
            }
            onImageLoaded?(image)
            return
        }
        guard !Task.isCancelled else { return }
        // One retry so a transient failure (rate-limit, blip, a cancelled
        // neighbour request) doesn't leave a permanent placeholder.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        if let image = try? await ImagePipeline.shared.image(for: request) {
            guard !Task.isCancelled else { return }
            StickyArtwork.store(image, for: normalized)
            loadedKey = normalized
            withAnimation(.easeInOut(duration: 0.2)) {
                loadedImage = image
            }
            onImageLoaded?(image)
        }
    }

    private var placeholderView: some View {
        Image(systemName: "music.note")
            .resizable()
            .scaledToFit()
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
    }
}

private let thumbnailCropRegex = try? NSRegularExpression(pattern: "(?<=[sh]\\d+)-c")
private let thumbnailSizeRegex = try? NSRegularExpression(pattern: "w(\\d+)-h(\\d+)")

private func normalizeThumbnailURL(_ urlString: String, pixels: Int) -> String {
    var url = urlString

    if let crop = thumbnailCropRegex {
        url = crop.stringByReplacingMatches(in: url, range: NSRange(url.startIndex..., in: url), withTemplate: "")
    }

    // Apple serves arbitrary square sizes from its image CDN. Match the
    // requested rung so small rows never download a 1200px asset.
    if url.contains("mzstatic.com") {
        url = url.replacingOccurrences(
            of: #"(?<=/)\d+x\d+(?=[^/]*\.[^/]+$)"#,
            with: "\(pixels)x\(pixels)",
            options: .regularExpression
        )
    }

    if url.contains("googleusercontent.com") || url.contains("ggpht.com") {
        if let match = thumbnailSizeRegex,
           let result = match.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
           let wRange = Range(result.range(at: 1), in: url),
           let hRange = Range(result.range(at: 2), in: url),
           let w = Int(url[wRange]),
           let h = Int(url[hRange]) {
            let size = "w\(pixels)-h\(pixels)"
            if size != "w\(w)-h\(h)" {
                url = url.replacingOccurrences(of: "w\(w)-h\(h)", with: size)
            }
        } else if let base = url.split(separator: "=").first {
            // Bare CDN URL with no size params: pin an explicit size instead
            // of trusting the server default.
            url = String(base) + "=w\(pixels)-h\(pixels)"
        }
    }

    return url
}
