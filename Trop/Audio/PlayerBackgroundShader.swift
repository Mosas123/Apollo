import SwiftUI
import UIKit

/// Animated, blurred cover backdrop for the full player: a Metal distortion
/// shader driven by `TimelineView` (WWDC "Compose advanced graphics effects").
struct PlayerBackgroundShader: View {
    let image: Image?
    let isPlaying: Bool

    var body: some View {
        GeometryReader { geometry in
            // 15 fps: the full-screen 80-pt blur + distortion is the most
            // expensive per-frame effect in the app; the motion is slow enough
            // that 15 fps reads the same while cutting GPU work ~40%.
            TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isPlaying)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                Group {
                    if let image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 80)
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
        .ignoresSafeArea(.container)
        .allowsHitTesting(false)
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
