import PulseCore
import SwiftUI

/// One horizon: a header, up to `collapseLimit` rows, then "Show N more".
/// §4.1: fixed order, zero-item sections omitted by the caller, expansion is
/// inline and per-session.
///
/// Deliberately a plain `VStack`, not a pinned `Section`: the board only has four
/// sections, and a pinned header over glass rows reads as a heavy grey band on a
/// translucent canvas.
public struct BoardSectionView: View {
    let horizon: Horizon
    let items: [PulseItem]
    let visibleCount: Int
    let isExpanded: Bool
    let now: Date
    let lastViewedAt: Date?
    var onToggle: () -> Void
    var onRowOpen: (PulseItem) -> Void
    var onRowAction: (PulseItem, BoardItemRow.LocalAction) -> Void

    public init(
        horizon: Horizon,
        items: [PulseItem],
        visibleCount: Int,
        isExpanded: Bool,
        now: Date,
        lastViewedAt: Date?,
        onToggle: @escaping () -> Void,
        onRowOpen: @escaping (PulseItem) -> Void,
        onRowAction: @escaping (PulseItem, BoardItemRow.LocalAction) -> Void
    ) {
        self.horizon = horizon
        self.items = items
        self.visibleCount = visibleCount
        self.isExpanded = isExpanded
        self.now = now
        self.lastViewedAt = lastViewedAt
        self.onToggle = onToggle
        self.onRowOpen = onRowOpen
        self.onRowAction = onRowAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.s) {
            PulseSectionHeader(horizon: horizon, count: items.count)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: PulseSpacing.cardGap) {
                ForEach(Array(items.prefix(visibleCount))) { item in
                    BoardItemRow(
                        item: item,
                        horizon: horizon,
                        now: now,
                        isNew: item.isNew(since: lastViewedAt),
                        onAction: { onRowAction(item, $0) },
                        onOpen: { onRowOpen(item) }
                    )
                }
            }

            if hiddenBeyondLimit > 0 || isExpanded {
                showAllControl
                    .padding(.top, PulseSpacing.xxs)
            }
        }
        .padding(.horizontal, PulseSpacing.screenMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hiddenBeyondLimit: Int { max(0, items.count - horizon.collapseLimit) }

    /// §4.1: "Show 4 more in Now". The row noun never appears here because the
    /// horizon is named, so the only pluralisation risk is the number itself --
    /// and "Show 1 more" is already correct. Kept as a property so the AX label and
    /// the visible text cannot drift.
    private var showMoreTitle: String {
        BoardCopy.showMore(hiddenBeyondLimit, in: horizon)
    }

    private var showAllControl: some View {
        Button(action: onToggle) {
            HStack(spacing: PulseSpacing.xxs) {
                Text(isExpanded ? "Show less" : showMoreTitle)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                if !isExpanded {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                }
            }
            .foregroundStyle(PulseColor.horizonNext)
            .frame(maxWidth: .infinity, minHeight: PulseSpacing.minimumHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? BoardCopy.showFewer(in: horizon) : showMoreTitle)
        .accessibilityIdentifier("board.showAll.\(horizon.rawValue)")
    }
}
