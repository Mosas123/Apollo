import SwiftUI

/// Shared measurement for floating tab headers.
struct TabHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Progressive variable blur + tint drawn behind a floating tab header, so the
/// content scrolls underneath and blurs toward the top (Apple Music style).
struct ProgressiveBlurUnderlay: View {
    let height: CGFloat
    var maxBlurRadius: CGFloat = 5

    var body: some View {
        let total = height + 64
        VariableBlurView(maxBlurRadius: maxBlurRadius, direction: .blurredTopClearBottom)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Color(.systemBackground).opacity(0.85), location: 0),
                        .init(color: Color(.systemBackground).opacity(0.55), location: min(90 / max(total, 1), 0.9)),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: total)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}
