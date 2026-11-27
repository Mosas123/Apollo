// Vendored (MIT) from dominikmartn/ProgressiveBlurHeader
import SwiftUI

// MARK: - PreferenceKey

private struct HeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - StickyBlurHeader

/// A sticky header with a progressive blur effect — content scrolls freely
/// underneath and becomes increasingly blurred, never clipped.
///
/// Uses the same (obfuscated) private API that Apple uses for progressive blur
/// in Music, Photos, etc. via [VariableBlur](https://github.com/nikstar/VariableBlur).
///
/// ```swift
/// StickyBlurHeader {
///     HStack {
///         Text("Title").font(.headline)
///         Spacer()
///         Button("Action") { }
///     }
///     .padding()
/// } content: {
///     ForEach(0..<50) { i in
///         Text("Row \(i)").padding()
///     }
/// }
/// ```
public struct StickyBlurHeader<Header: View, Content: View>: View {

    private let maxBlurRadius: CGFloat
    private let fadeExtension: CGFloat
    private let tintOpacityTop: Double
    private let tintOpacityMiddle: Double
    private let header: () -> Header
    private let content: () -> Content

    @State private var headerHeight: CGFloat = 76
    @Environment(\.colorScheme) private var colorScheme

    /// Creates a sticky header with progressive blur.
    ///
    /// - Parameters:
    ///   - maxBlurRadius: Maximum blur intensity at the top edge. `5` = subtle, `10` = moderate, `20` = strong. Default: `5`.
    ///   - fadeExtension: How far (in pt) the blur extends below the header. Larger = softer fade. Default: `64`.
    ///   - tintOpacityTop: Tint darkness at the very top (behind Dynamic Island). Default: `0.7`.
    ///   - tintOpacityMiddle: Tint darkness at the header's vertical center. Default: `0.5`.
    ///   - header: The header content. **Must not have an opaque background** — the blur IS the background.
    ///   - content: The scrollable content below the header.
    public init(
        maxBlurRadius: CGFloat = 5,
        fadeExtension: CGFloat = 64,
        tintOpacityTop: Double = 0.7,
        tintOpacityMiddle: Double = 0.5,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.maxBlurRadius = maxBlurRadius
        self.fadeExtension = fadeExtension
        self.tintOpacityTop = tintOpacityTop
        self.tintOpacityMiddle = tintOpacityMiddle
        self.header = header
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .top) {

            // Layer 1: Scrollable content — never clipped
            ScrollView {
                content()
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: headerHeight)
            }

            // Layer 2: Progressive blur + tint fade
            let totalHeight = headerHeight + fadeExtension
            VariableBlurView(
                maxBlurRadius: maxBlurRadius,
                direction: .blurredTopClearBottom
            )
            .overlay {
                LinearGradient(stops: [
                    .init(color: fadeTint.opacity(tintOpacityTop), location: 0),
                    .init(color: fadeTint.opacity(tintOpacityMiddle), location: 90 / totalHeight),
                    .init(color: fadeTint.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(height: totalHeight)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            // Layer 3: Header — floats above blur, NO opaque background
            header()
                .overlay {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: HeaderHeightKey.self,
                            value: geo.size.height
                        )
                    }
                }
        }
        .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
    }

    private var fadeTint: Color {
        colorScheme == .dark ? .black : .white
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Light") {
    StickyBlurHeader {
        HStack {
            Circle().fill(.ultraThinMaterial).frame(width: 44, height: 44)
            Spacer()
            Text("Header").font(.headline)
            Spacer()
            Circle().fill(.ultraThinMaterial).frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    } content: {
        VStack(spacing: 0) {
            ForEach(0..<30) { i in
                HStack {
                    Circle()
                        .fill(Color(hue: Double(i) / 30, saturation: 0.6, brightness: 0.9))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text("Item \(i)").font(.body.bold())
                        Text("Scroll to see the blur effect").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Divider().padding(.leading, 76)
            }
        }
    }
    .background(Color(.systemBackground))
}

#Preview("Dark") {
    StickyBlurHeader(maxBlurRadius: 10) {
        HStack {
            Circle().fill(.ultraThinMaterial).frame(width: 44, height: 44)
            Spacer()
            Text("Header").font(.headline)
            Spacer()
            Circle().fill(.ultraThinMaterial).frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    } content: {
        VStack(spacing: 0) {
            ForEach(0..<30) { i in
                HStack {
                    Circle()
                        .fill(Color(hue: Double(i) / 30, saturation: 0.6, brightness: 0.9))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text("Item \(i)").font(.body.bold())
                        Text("Scroll to see the blur effect").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Divider().padding(.leading, 76)
            }
        }
    }
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}
#endif
