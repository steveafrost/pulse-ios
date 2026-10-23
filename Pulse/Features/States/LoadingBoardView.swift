import SwiftUI

/// §8.1: four 24pt headers and three 92pt card placeholders, `.redacted`, no
/// spinner, no shimmer (§10 Reduce Motion).
public struct LoadingBoardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: PulseSpacing.s) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(PulseColor.surfaceCard.opacity(0.5))
                        .frame(width: 120, height: PulseSpacing.xl)
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: PulseRadius.card, style: .continuous)
                            .fill(PulseColor.surfaceCard.opacity(0.5))
                            .frame(height: 92)
                    }
                }
                .padding(.horizontal, PulseSpacing.screenMargin)
                .opacity(index == 0 ? 1 : 0.6)
            }
        }
        .padding(.top, PulseSpacing.m)
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading your board")
        .accessibilityIdentifier("board.loading")
    }
}
