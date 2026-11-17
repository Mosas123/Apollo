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
        extractDominantColors()[0]
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
            guard let bin = bins[key], bin.count > 0 else { return nil }
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
            centers = sums.filter { $0.count > 0 }.map {
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
