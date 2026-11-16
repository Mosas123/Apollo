import SwiftUI
import UIKit

/// Animated, blurred cover backdrop for the full player: a Metal distortion
/// shader driven by `TimelineView` (WWDC "Compose advanced graphics effects").
struct PlayerBackgroundShader: View {
    let image: UIImage?
    let isPlaying: Bool

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                Group {
                    if let image {
                        Image(uiImage: image)
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
