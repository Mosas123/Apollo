//
//  UIImage+ColorExtraction.swift
//  Trop
//
//  Created by 686udjie on 13/07/2026.
//

import UIKit
import SwiftUI

extension UIImage {
    /// Album pages and artist/player gradients share the same population-based
    /// palette, rather than choosing an isolated high-saturation pixel.
    func extractAlbumBackdropColor() -> Color {
        extractDetailBackdropColor()
    }

    /// Blend the midtones across the artwork instead of using one dark cluster.
    /// This preserves warm/cool colour families (foliage + earth becomes olive).
    func extractDetailBackdropColor() -> Color {
        guard let image = cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return .gray }
        let side = 40
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &bytes, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return .gray }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var sums = [Double](repeating: 0, count: 3)
        var total = 0.0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Double(bytes[offset + 3]) / 255
            guard alpha > 0.8 else { continue }
            let rgb = (0..<3).map { min(1, Double(bytes[offset + $0]) / 255 / alpha) }
            let high = rgb.max() ?? 0
            let low = rgb.min() ?? 0
            guard high > 0.12, low < 0.90 else { continue }
            let saturation = (high - low) / high
            let weight = 0.4 + 0.6 * saturation
            for channel in 0..<3 { sums[channel] += rgb[channel] * weight }
            total += weight
        }
        guard total > 0 else { return extractDominantColors()[0] }
        return Color(red: sums[0] / total, green: sums[1] / total, blue: sums[2] / total)
    }

    func extractDominantColors() -> [Color] {
        let fallback = [Color(red: 0.15, green: 0.15, blue: 0.18),
                        Color(red: 0.05, green: 0.05, blue: 0.06)]
        guard let image = cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return fallback }
        let side = 40
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: &data, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: bitmap) else { return fallback }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        struct Sample {
            var r: Double
            var g: Double
            var b: Double
            var count: Double
            var saturation: Double {
                let high = max(r, g, b)
                return high == 0 ? 0 : (high - min(r, g, b)) / high
            }
            func distance(to other: Sample) -> Double {
                // Weighted RGB distance keeps nearby shades in one family.
                0.30 * pow(r - other.r, 2) + 0.59 * pow(g - other.g, 2) + 0.11 * pow(b - other.b, 2)
            }
            var color: Color { Color(red: r, green: g, blue: b) }
        }
        var bins: [Int: Sample] = [:]
        for offset in stride(from: 0, to: data.count, by: 4) {
            let alpha = Double(data[offset + 3]) / 255
            guard alpha > 0.8 else { continue }
            // CGContext stores premultiplied channels; undo that before analysis.
            let r = min(1, Double(data[offset]) / 255 / alpha)
            let g = min(1, Double(data[offset + 1]) / 255 / alpha)
            let b = min(1, Double(data[offset + 2]) / 255 / alpha)
            let key = Int(r * 15) * 256 + Int(g * 15) * 16 + Int(b * 15)
            var bin = bins[key] ?? Sample(r: 0, g: 0, b: 0, count: 0)
            bin.r += r; bin.g += g; bin.b += b; bin.count += 1
            bins[key] = bin
        }
        // Sort keys to make equal-population palettes reproducible.
        let all = bins.keys.sorted().compactMap { key -> Sample? in
            guard let bin = bins[key], !bin.count.isZero else { return nil }
            return Sample(r: bin.r / bin.count, g: bin.g / bin.count,
                          b: bin.b / bin.count, count: bin.count)
        }
        guard !all.isEmpty else { return fallback }
        let midtones = all.filter { max($0.r, $0.g, $0.b) > 0.10 && min($0.r, $0.g, $0.b) < 0.92 }
        let midtoneCount = midtones.reduce(0) { $0 + $1.count }
        let totalCount = all.reduce(0) { $0 + $1.count }
        // Mostly monochrome covers keep their real neutral palette. A tiny
        // colourful logo must not tint an otherwise black/white page.
        let samples = midtoneCount >= totalCount * 0.15 ? midtones : all
        guard let seed = samples.max(by: { $0.count < $1.count }) else { return fallback }
        var centers = [seed]
        while centers.count < min(5, samples.count) {
            let next = samples.max { lhs, rhs in
                let left = centers.map { lhs.distance(to: $0) }.min() ?? 0
                let right = centers.map { rhs.distance(to: $0) }.min() ?? 0
                return left * sqrt(lhs.count) < right * sqrt(rhs.count)
            }!
            guard (centers.map { next.distance(to: $0) }.min() ?? 0) > 0.002 else { break }
            centers.append(next)
        }
        // A few bounded k-means passes merge shades split by quantisation.
        for _ in 0..<8 {
            var sums = centers.map { _ in Sample(r: 0, g: 0, b: 0, count: 0) }
            for sample in samples {
                let index = centers.indices.min { sample.distance(to: centers[$0]) < sample.distance(to: centers[$1]) }!
                sums[index].r += sample.r * sample.count
                sums[index].g += sample.g * sample.count
                sums[index].b += sample.b * sample.count
                sums[index].count += sample.count
            }
            centers = sums.filter { !$0.count.isZero }.map {
                Sample(r: $0.r / $0.count, g: $0.g / $0.count, b: $0.b / $0.count, count: $0.count)
            }
        }
        let ranked = centers.sorted {
            $0.count * (0.85 + 0.15 * $0.saturation) > $1.count * (0.85 + 0.15 * $1.saturation)
        }
        guard let primary = ranked.first else { return fallback }
        let population = samples.reduce(0) { $0 + $1.count }
        let secondary = ranked.dropFirst().first {
            $0.count >= population * 0.10 && $0.distance(to: primary) > 0.025
        }
        return [primary.color, secondary?.color ?? Color(red: primary.r * 0.65,
                                                          green: primary.g * 0.65,
                                                          blue: primary.b * 0.65)]
    }

    func centerCroppedSquare() -> UIImage {
        guard let cgImage = self.cgImage else { return self }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        guard size.width > 0, size.height > 0 else { return self }

        let contentRect = trimmedContentRect(of: cgImage, size: size)
        let side = min(contentRect.width, contentRect.height)
        let square = CGRect(
            x: contentRect.origin.x + (contentRect.width - side) / 2,
            y: contentRect.origin.y + (contentRect.height - side) / 2,
            width: side,
            height: side
        )

        guard let cropped = cgImage.cropping(to: square) else { return self }
        return UIImage(cgImage: cropped, scale: self.scale, orientation: self.imageOrientation)
    }

    /// Scans the image at reduced resolution to find the bounding box of non-black content,
    /// removing uniform (black) borders
    private func trimmedContentRect(of cgImage: CGImage, size: CGSize) -> CGRect {
        let maxDim = 160
        let scale = min(1, CGFloat(maxDim) / max(size.width, size.height))
        let w = max(1, Int(size.width * scale))
        let h = max(1, Int(size.height * scale))

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * w
        var raw = [UInt8](repeating: 0, count: w * h * bytesPerPixel)
        guard let ctx = CGContext(
            data: &raw,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return CGRect(origin: .zero, size: size) }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let isBlack: (Int, Int) -> Bool = { x, y in
            let o = y * bytesPerRow + x * bytesPerPixel
            let r = Double(raw[o]) / 255
            let g = Double(raw[o + 1]) / 255
            let b = Double(raw[o + 2]) / 255
            return (r + g + b) / 3 < 0.08
        }

        let blackRatioThreshold = 0.9

        func columnIsBorder(_ x: Int) -> Bool {
            var black = 0
            for y in 0..<h where isBlack(x, y) { black += 1 }
            return Double(black) / Double(h) >= blackRatioThreshold
        }
        func rowIsBorder(_ y: Int) -> Bool {
            var black = 0
            for x in 0..<w where isBlack(x, y) { black += 1 }
            return Double(black) / Double(w) >= blackRatioThreshold
        }

        var minX = 0
        while minX < w && columnIsBorder(minX) { minX += 1 }
        var maxX = w - 1
        while maxX > minX && columnIsBorder(maxX) { maxX -= 1 }
        var minY = 0
        while minY < h && rowIsBorder(minY) { minY += 1 }
        var maxY = h - 1
        while maxY > minY && rowIsBorder(maxY) { maxY -= 1 }

        guard maxX > minX, maxY > minY else { return CGRect(origin: .zero, size: size) }

        let rx = CGFloat(minX) / scale
        let ry = CGFloat(minY) / scale
        let rw = CGFloat(maxX - minX + 1) / scale
        let rh = CGFloat(maxY - minY + 1) / scale
        return CGRect(x: rx, y: ry, width: rw, height: rh)
    }
}

/// Opaque artwork-derived surfaces: light mode changes the tone rather than
/// mixing a faint tint over white. Calibrated against the supplied screenshots.
struct DetailArtworkPalette {
    enum Surface { case album, artist }
    let top: Color
    let bottom: Color
    let playInk: Color

    init(seed: Color, isDark: Bool, surface: Surface) {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(seed).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let neutral = saturation < 0.06
        let targetSaturation: CGFloat
        let targetBrightness: CGFloat
        let falloff: CGFloat
        switch surface {
        case .album:
            targetSaturation = neutral ? 0 : min(0.95, isDark ? saturation * 0.75 + 0.40 : saturation * 0.55 + 0.16)
            targetBrightness = min(0.64, isDark ? brightness * 0.35 + 0.12 : brightness * 0.35 + 0.33)
            falloff = isDark ? 0.04 : 0.055
        case .artist:
            targetSaturation = neutral ? 0 : min(1, saturation * 1.15 + 0.08)
            targetBrightness = min(0.76, isDark ? brightness * 0.58 + 0.08 : brightness * 0.65 + 0.10)
            falloff = 0.025
        }
        // Keep a minimum 4.5:1 contrast against white for primary content.
        func readable(_ value: CGFloat) -> UIColor {
            var value = value
            for _ in 0..<40 {
                let color = UIColor(hue: hue, saturation: targetSaturation, brightness: value, alpha: 1)
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                func linear(_ channel: CGFloat) -> Double {
                    let channel = Double(channel)
                    return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
                }
                let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
                if 1.05 / (luminance + 0.05) >= 4.5 { return color }
                value *= 0.96
            }
            return UIColor(hue: hue, saturation: targetSaturation, brightness: value, alpha: 1)
        }
        top = Color(uiColor: readable(targetBrightness))
        bottom = Color(uiColor: readable(max(0.08, targetBrightness - falloff)))
        playInk = Color(uiColor: readable(min(targetBrightness, 0.32)))
    }
}

/// Shared background for artwork-led collection pages.
struct DetailArtworkBackground: View {
    let seed: Color?
    let isDark: Bool

    var body: some View {
        Group {
            if let seed {
                let palette = DetailArtworkPalette(seed: seed, isDark: isDark, surface: .album)
                LinearGradient(stops: [
                    .init(color: palette.top, location: 0),
                    .init(color: palette.bottom, location: 0.75),
                    .init(color: palette.bottom, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            } else {
                Color(.systemBackground)
            }
        }
        .ignoresSafeArea(.container)
    }
}

/// The player has a deeper vertical falloff than collection detail pages.
struct PlayerArtworkPalette {
    let top: Color
    let bottom: Color

    init(seed: Color, isDark: Bool) {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(seed).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let neutral = saturation < 0.06
        // A gentle warm highlight; the lower surface retains the source hue.
        let highlightHue = (hue - 0.065 * sin(hue * 2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
        let highlightSaturation = neutral ? 0 : min(0.85, saturation * 0.5 + 0.25)
        let lowerSaturation = neutral ? 0 : min(0.85, saturation * 0.7 + 0.20)
        // Caps keep primary white text readable, including on very bright art.
        let highlightBrightness = min(0.43, brightness * 0.45 + (isDark ? 0.18 : 0.23))
        let lowerBrightness = min(0.25, brightness * 0.15 + (isDark ? 0.09 : 0.12))
        top = Color(uiColor: UIColor(hue: highlightHue, saturation: highlightSaturation,
                                     brightness: highlightBrightness, alpha: 1))
        bottom = Color(uiColor: UIColor(hue: hue, saturation: lowerSaturation,
                                        brightness: lowerBrightness, alpha: 1))
    }
}
