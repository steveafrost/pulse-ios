import SwiftUI

/// §7.5 — the board's one signature moment: rows settle in, top to bottom.
///
/// The board is checked a hundred times a day, so this is deliberately a *breath*,
/// not a performance: a 10pt rise and a fade, 0.34s, each row 32ms after the one
/// above it and capped so a long board still finishes inside a quarter second.
///
/// **Reduce Motion shows the final state immediately.** Not a faster animation —
/// `reduceMotion` makes `body` return the content untouched, so nothing animates,
/// nothing is delayed, and there is no window where a row is half-arrived. That is
/// the difference between honouring the setting and merely shortening it.
public struct LoadIn: ViewModifier {
    let index: Int

    @Environment(\.pulseMotion) private var motion
    @State private var hasSettled = false

    public init(index: Int) {
        self.index = index
    }

    private var delay: Double {
        min(Double(index) * ThirdHandMetrics.loadInStagger, ThirdHandMetrics.loadInStaggerCap)
    }

    public func body(content: Content) -> some View {
        if motion.reduceMotion {
            // Final state, immediately. No transition, no delay, no animation.
            content
        } else {
            content
                .opacity(hasSettled ? 1 : 0)
                .offset(y: hasSettled ? 0 : ThirdHandMetrics.loadInRise)
                .onAppear {
                    guard !hasSettled else { return }
                    withAnimation(.easeOut(duration: 0.34).delay(delay)) {
                        hasSettled = true
                    }
                }
        }
    }
}

extension View {
    /// Settle this view in at `index` in a staggered group (§7.5).
    public func loadIn(index: Int) -> some View {
        modifier(LoadIn(index: index))
    }
}