import ThirdHandCore
import SwiftUI

/// §5: the item row is the product. One opaque card, a leading horizon rail, a
/// kind glyph, title (+ detail), the trailing 44pt completion control and an
/// overflow menu, then the meta line.
///
/// The row owns exactly one piece of local state: the two-phase completion
/// (`marking` -> `removing`) from §7.2, which cannot live in the view model
/// because it is presentation timing.
public struct BoardItemRow: View {
    public enum LocalAction: Sendable {
        case done
        case snooze
        case dismiss
        case reopen
        case copy(String)
        case open(URL)
    }

    let item: ThirdHandItem
    let horizon: Horizon
    let now: Date
    let isNew: Bool
    var onAction: (LocalAction) -> Void
    var onOpen: () -> Void

    @Environment(\.pulseMotion) private var motion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isMarking = false
    @State private var isPressed = false

    public init(
        item: ThirdHandItem,
        horizon: Horizon,
        now: Date,
        isNew: Bool = false,
        onAction: @escaping (LocalAction) -> Void,
        onOpen: @escaping () -> Void
    ) {
        self.item = item
        self.horizon = horizon
        self.now = now
        self.isNew = isNew
        self.onAction = onAction
        self.onOpen = onOpen
    }

    public var body: some View {
        card
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Opens details")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("board.row.\(item.id)")
            .accessibilityActions { rotorActions }
            .onTapGesture(perform: onOpen)
            .accessibilityAction(.default, onOpen)
    }

    // MARK: Card

    private var card: some View {
        HStack(alignment: .top, spacing: ThirdHandSpacing.s) {
            if horizon.hasRail {
                RoundedRectangle(cornerRadius: ThirdHandRadius.rail, style: .continuous)
                    .fill(item.railTint(horizon: horizon, now: now))
                    .frame(width: ThirdHandMetrics.railWidth)
                    .accessibilityHidden(true)
            }

            /// The meta strip is a sibling of the title block, not a child of it:
            /// inside the text column the horizontal scroller is clipped to that
            /// column's width, so dates truncate to "Oct 2".
            VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
                if dynamicTypeSize >= .accessibility3 {
                    /// §3 at AX3+: the completion control moves below the text.
                    /// Beside a 3xl title it leaves about eight characters a line,
                    /// which turns every row into a column.
                    VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
                        HStack(alignment: .top, spacing: ThirdHandSpacing.s) {
                            kindGlyph
                            titleBlock
                        }
                        metaLine
                        trailingControls
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    HStack(alignment: .top, spacing: ThirdHandSpacing.s) {
                        kindGlyph
                        titleBlock
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        trailingControls
                    }
                    metaLine
                }
            }
            /// §5.1 rule 1: rail rows inset text an extra 3+12pt.
            .padding(.leading, horizon.hasRail ? ThirdHandSpacing.s : 0)
        }
        .padding(.horizontal, ThirdHandSpacing.m)
        .padding(.vertical, 14)
        .frame(minHeight: minimumHeight, alignment: .topLeading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous))
        .overlay {
            if isNew {
                RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous)
                    .strokeBorder(ThirdHandColor.horizonNext.opacity(0.45), lineWidth: ThirdHandMetrics.hairline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(item.status == .done ? 0.6 : (item.isSnoozed ? 0.7 : 1))
        .animation(motion.completionFlash, value: isMarking)
        .contentShape(RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous))
    }

    private var rowBackground: Color {
        isMarking ? ThirdHandColor.statusDone.opacity(0.12) : (isPressed ? ThirdHandColor.surfaceCardPressed : ThirdHandColor.surfaceCard)
    }

    /// §4: 72 title-only / 92 title+detail / 112 title+detail+two meta chips.
    private var minimumHeight: CGFloat {
        if item.detail.isEmpty { return ThirdHandSpacing.rowTitleMinHeight }
        return ThirdHandSpacing.rowTitleDetailMinHeight
    }

    // MARK: Content

    private var kindGlyph: some View {
        HStack(spacing: ThirdHandSpacing.xxs) {
            if isNew {
                Circle()
                    .fill(ThirdHandColor.horizonNext)
                    .frame(width: ThirdHandMetrics.newnessDot, height: ThirdHandMetrics.newnessDot)
                    .accessibilityHidden(true)
            }
            Image(systemName: item.kind.systemImage)
                .font(.system(size: ThirdHandMetrics.kindGlyphSize, weight: .semibold))
                .foregroundStyle(item.kind.tint)
                .accessibilityHidden(true)
        }
        .frame(width: ThirdHandMetrics.kindGlyphSize + (isNew ? ThirdHandMetrics.newnessDot + ThirdHandSpacing.xxs : 0))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
            Text(item.title)
                .font(ThirdHandTypography.itemTitle)
                .foregroundStyle(ThirdHandColor.textPrimary)
                /// §3: the 2-line limit is removed at AX1+.
                .lineLimit(dynamicTypeSize < .accessibility1 ? 2 : nil)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            /// §3: detail hides on the board at AX3+.
            if !item.detail.isEmpty, dynamicTypeSize < .accessibility3 {
                Text(item.detail)
                    .font(ThirdHandTypography.itemDetail)
                    .foregroundStyle(ThirdHandColor.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var metaLine: some View {
        // §3: one line at standard sizes; a vertical stack at AX1+. A single
        // horizontal line cannot fit two chips plus a date at AX5 and it widens
        // the card past the screen instead of truncating.
        Group {
            if dynamicTypeSize >= .accessibility1 {
                VStack(alignment: .leading, spacing: ThirdHandSpacing.xxs) {
                    metaChips
                    metaTiming
                }
            } else {
                HStack(spacing: ThirdHandSpacing.xs) {
                    metaChips
                    metaTiming
                }
                .lineLimit(1)
            }
        }
        .padding(.top, ThirdHandSpacing.xxs)
    }

    /// §3: chips stop scaling and drop their fill at AX2+, becoming plain
    /// `·`-separated tokens. At AX5 a chip's own width leaves room for two
    /// letters, which is worse than the word it was standing in for.
    @ViewBuilder
    private var metaChips: some View {
        if dynamicTypeSize >= .accessibility2 {
            Text(item.sourceIdentity.title + " · " + item.kind.title)
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textSecondary)
        } else {
            HStack(spacing: ThirdHandSpacing.xs) {
                ThirdHandBadge(source: item.sourceIdentity)
                ThirdHandBadge(kind: item.kind)
            }
        }
    }

    /// The due date (or snooze target) and how long since the item was seen.
    /// `ViewThatFits` drops the age rather than truncating it to "12h a…": the
    /// date is what the row is for, and the age is on the detail sheet.
    private var metaTiming: some View {
        ViewThatFits(in: .horizontal) {
            timingRow(showsAge: true)
            timingRow(showsAge: false)
        }
    }

    private func timingRow(showsAge: Bool) -> some View {
        HStack(spacing: ThirdHandSpacing.xs) {
            if item.isSnoozed, let until = item.snoozedUntil {
                Label(ThirdHandDateFormat.snoozeUntil(until), systemImage: "moon.zzz.fill")
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(ThirdHandColor.statusSnoozed)
                    .lineLimit(1)
            } else if let due = item.due {
                Text(ThirdHandDateFormat.dueChip(due, now: now))
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(ThirdHandColor.textTertiary)
                    .lineLimit(1)
            }

            if showsAge {
                Text(ThirdHandDateFormat.relative(item.lastSeenAt, now: now))
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(ThirdHandColor.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Trailing controls (§5.1 rules 4 and 5)

    private var trailingControls: some View {
        HStack(spacing: ThirdHandSpacing.xxs) {
            completionButton
            if showsOverflow {
                overflowMenu
            }
        }
    }

    private var showsOverflow: Bool {
        !item.quickActions.isEmpty || item.url != nil || item.status == .done || item.status == .snoozed
    }

    private var completionButton: some View {
        Button(action: markDone) {
            Image(systemName: completionGlyph)
                .font(.title3)
                .foregroundStyle(isMarking ? ThirdHandColor.statusDone : ThirdHandColor.textSecondary)
                .symbolEffect(.bounce, value: motion.allowsSymbolEffect && isMarking)
                .frame(width: ThirdHandSpacing.minimumHitTarget, height: ThirdHandSpacing.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(completionLabel)
        .accessibilityIdentifier("board.row.done.\(item.id)")
    }

    private var completionGlyph: String {
        if isMarking || item.status == .done { return "checkmark.circle.fill" }
        if item.status == .snoozed { return "moon.zzz.fill" }
        if item.status == .waiting { return "arrow.uturn.backward.circle" }
        return "checkmark.circle"
    }

    private var completionLabel: String {
        if item.status == .done { return "Reopen this item" }
        return "Mark done"
    }

    private var overflowMenu: some View {
        Menu {
            if item.status == .done || item.status == .dismissed {
                Button("Reopen", systemImage: "arrow.uturn.backward") { onAction(.reopen) }
            } else {
                Button("Snooze", systemImage: "moon.zzz") { onAction(.snooze) }
                Button("Dismiss", systemImage: "xmark.circle") { onAction(.dismiss) }
            }
            if let text = item.quickActions.first(where: { $0.text != nil })?.text {
                Button("Copy action text", systemImage: "doc.on.doc") { onAction(.copy(text)) }
            }
            if let url = item.url.flatMap(URL.init(string:)) {
                Button("Open link", systemImage: "arrow.up.right.square") { onAction(.open(url)) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(ThirdHandColor.textSecondary)
                .frame(width: ThirdHandSpacing.minimumHitTarget, height: ThirdHandSpacing.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More actions for \(item.title)")
        .accessibilityIdentifier("board.row.more.\(item.id)")
    }

    // MARK: Completion (§7.2)

    private func markDone() {
        guard item.status != .done else {
            onAction(.reopen)
            return
        }
        withAnimation(motion.completionFlash) { isMarking = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(ThirdHandMotion.completionFlashDuration * 1000)))
            onAction(.done)
        }
    }

    // MARK: VoiceOver (§5.3)

    var accessibilityLabel: String {
        "\(item.title). \(item.kind.spokenLabel). \(item.sourceIdentity.spokenLabel)."
    }

    var accessibilityValue: String {
        var parts: [String] = []
        if !item.detail.isEmpty { parts.append(item.detail) }
        if item.isSnoozed, let until = item.snoozedUntil {
            parts.append("Snoozed \(ThirdHandDateFormat.snoozeUntil(until))")
        } else {
            parts.append(ThirdHandDateFormat.duePhrase(item.due, now: now))
        }
        let people = ThirdHandPeople.spokenPhrase(item.people)
        if !people.isEmpty { parts.append(people) }
        parts.append(ThirdHandDateFormat.relativePhrase(item.lastSeenAt, now: now))
        switch item.status {
        case .waiting: parts.append("waiting on someone else")
        case .snoozed: parts.append("snoozed")
        case .done: parts.append("done")
        case .dismissed: parts.append("dismissed")
        default: break
        }
        if isNew { parts.append("new since you last looked") }
        return parts.joined(separator: ". ")
    }

    @ViewBuilder
    private var rotorActions: some View {
        Button("Mark done") { onAction(.done) }
        Button("Snooze") { onAction(.snooze) }
        Button("Dismiss") { onAction(.dismiss) }
        if let text = item.quickActions.first(where: { $0.text != nil })?.text {
            Button("Copy action") { onAction(.copy(text)) }
        }
        if let url = item.url.flatMap(URL.init(string:)) {
            Button("Open link") { onAction(.open(url)) }
        }
        if item.status == .done {
            Button("Reopen") { onAction(.reopen) }
        }
    }
}
