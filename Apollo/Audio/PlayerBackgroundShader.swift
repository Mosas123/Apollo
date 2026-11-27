import SwiftUI
import UIKit

/// Animated, blurred cover backdrop for the full player: a Metal distortion
/// shader driven by `TimelineView` (WWDC "Compose advanced graphics effects").
///
/// The "blur" is baked once into a tiny bitmap and upscaled, so the shader
/// samples a cheap texture instead of re-running an 80-pt blur every frame.
struct PlayerBackgroundShader: View {
    let image: UIImage?
    let isPlaying: Bool

    @State private var backdrop: Image?

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isPlaying)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                Group {
                    if let backdrop {
                        backdrop
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        Color.clear
                    }
                }
                .opacity(0.55)
                .distortionEffect(
                    ShaderLibrary.playerWarp(
                        .float(time),
                        .float2(geometry.size),
                        .float(14)
                    ),
                    maxSampleOffset: CGSize(width: 24, height: 24)
                )
            }
        }
        .task(id: image.map(ObjectIdentifier.init)) {
            backdrop = image.map(Self.makeBackdrop)
        }
        .ignoresSafeArea(.container)
        .allowsHitTesting(false)
    }

    /// Aspect-fills the cover into a ~40 pt square. Upscaling that bitmap to
    /// the screen produces the soft, heavy blur look at a fraction of the cost.
    private static func makeBackdrop(_ image: UIImage) -> Image {
        let side: CGFloat = 40
        let target = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let tiny = renderer.image { _ in
            let size = image.size
            guard size.width > 0, size.height > 0 else { return }
            let scale = max(target.width / size.width, target.height / size.height)
            let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
            let origin = CGPoint(
                x: (target.width - drawSize.width) / 2,
                y: (target.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return Image(uiImage: tiny)
    }
}


/// Subtle, time-driven distortion for artwork heroes (runs only while playing).
struct AnimatedDistortion<Content: View>: View {
    let size: CGSize
    let isPlaying: Bool
    var amplitude: CGFloat = 6
    @ViewBuilder var content: Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            content.distortionEffect(
                ShaderLibrary.playerWarp(
                    .float(time),
                    .float2(size),
                    .float(amplitude)
                ),
                maxSampleOffset: CGSize(width: amplitude * 2, height: amplitude * 2)
            )
        }
    }
}
