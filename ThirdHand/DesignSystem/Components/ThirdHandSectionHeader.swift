import SwiftUI
import ThirdHandCore

/// §4.1: a sticky header on an opaque `.bar` strip — it carries a label, so glass
/// is forbidden. §10: it is a VoiceOver header and reads "Now, 2 items".
public struct ThirdHandSectionHeader: View {
    let horizon: Horizon
    let count: Int
    /// §3: section hints hide at AX1+.
    @ScaledMetric(relativeTo: .footnote) private var scale: CGFloat = 1

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(horizon: Horizon, count: Int) {
        self.horizon = horizon
        self.count = count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xxs) {
            HStack(spacing: ThirdHandSpacing.xs) {
                Image(systemName: horizon.systemImage)
                    .font(ThirdHandTypography.sectionHeader)
                    .foregroundStyle(horizon.tint)
                    .accessibilityHidden(true)
                Text(horizon.title)
                    .font(ThirdHandTypography.sectionHeader)
                    .foregroundStyle(ThirdHandColor.textPrimary)
                Text("\(count)")
                    .font(ThirdHandTypography.sectionHeader)
                    .foregroundStyle(horizon.tint)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            if dynamicTypeSize < .accessibility1 {
                Text(horizon.hint)
                    .font(ThirdHandTypography.sectionHint)
                    .foregroundStyle(ThirdHandColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        /// No horizontal padding of its own and no `.bar` strip: the section view
        /// supplies the inset, and an opaque bar across the canvas reads as a
        /// stray grey band above the first card.
        .padding(.vertical, ThirdHandSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoardCopy.sectionHeader(horizon, count: count))
        .accessibilityAddTraits(.isHeader)
    }
}
