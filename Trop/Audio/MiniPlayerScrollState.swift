//
//  MiniPlayerScrollState.swift
//  Trop
//
//  Created by 686udjie on 19/08/2026.
//

import SwiftUI

/// Shared state driving the mini player's inline (minimized) layout.
/// The system's `tabViewBottomAccessoryPlacement` environment can lag behind
/// the actual tab bar state on scroll-back, so the scroll containers set this
/// directly to keep the mini player's content in sync with its position.
@Observable
final class MiniPlayerScrollState {
    var isInline = false
}

/// Flips `MiniPlayerScrollState.isInline` based on a scroll container's vertical
/// offset, matching the system's tab bar minimize behavior: collapsing when the
/// user scrolls down and restoring the moment they scroll back up.
struct MiniPlayerInlineOnScrollModifier: ViewModifier {
    @Environment(MiniPlayerScrollState.self) private var scrollState
    var headerHidden: Binding<Bool>? = nil
    @State private var directionAnchor: CGFloat?

    private let compactThreshold: CGFloat = 1

    init(headerHidden: Binding<Bool>? = nil) {
        self.headerHidden = headerHidden
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(
                for: CGFloat.self,
                of: { $0.contentOffset.y },
                action: { oldOffset, newOffset in
                    if let headerHidden {
                        let anchor = directionAnchor ?? oldOffset
                        if newOffset <= 20 {
                            directionAnchor = newOffset
                            if headerHidden.wrappedValue {
                                withAnimation(.easeInOut(duration: 0.2)) { headerHidden.wrappedValue = false }
                            }
                        } else if abs(newOffset - anchor) >= 20 {
                            let hide = newOffset > anchor
                            directionAnchor = newOffset
                            if hide != headerHidden.wrappedValue {
                                withAnimation(.easeInOut(duration: 0.2)) { headerHidden.wrappedValue = hide }
                            }
                        }
                    }
                    if newOffset > oldOffset, newOffset > compactThreshold {
                        guard !scrollState.isInline else { return }
                        scrollState.isInline = true
                    } else if newOffset < oldOffset {
                        guard scrollState.isInline else { return }
                        scrollState.isInline = false
                    }
                }
            )
    }
}
