import PulseCore
import SwiftUI
import WidgetKit

/// The Home Screen widget (issue #29): the Now count, and on medium the top three
/// items. Nothing here captures, reads EventKit or touches the network -- it renders
/// `board.json` from the app group and nothing else.
struct PulseHomeWidgetView: View {
    let entry: PulseEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            default: medium
            }
        }
        .containerBackground(for: .widget) { WidgetTheme.surface }
        // §11 / #29: one deep link for the whole widget; medium rows add their own.
        .widgetURL(URL(string: "pulse://board"))
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .privacySensitive(!entry.isPlaceholder)
    }

    // MARK: Small

    /// Now count as the hero numeral, the top item over two lines, and a staleness
    /// footer. §11's small-widget order.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(entry.snapshot.nowCount)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                Text("Now")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetCopy.countAccessibilityLabel(entry.snapshot.nowCount))

            Spacer(minLength: 4)

            if let top = entry.snapshot.topItem {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: WidgetTheme.glyph(forKind: top.kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(top.title)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 1 : 2)
                        .multilineTextAlignment(.leading)
                }
            } else {
                emptyState(compact: true)
            }

            Spacer(minLength: 0)

            Text(entry.isPlaceholder ? "now" : entry.snapshot.ageText(now: entry.date))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium

    /// Now header, then the top three items in board order with a priority mark, a
    /// kind glyph and a due hint, then "+N more".
    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(entry.snapshot.nowCount)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Now")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetCopy.countAccessibilityLabel(entry.snapshot.nowCount))

            if entry.snapshot.isEmpty {
                Spacer(minLength: 0)
                emptyState(compact: false)
                Spacer(minLength: 0)
            } else {
                // §11 says two rows for medium; #29 asks for the top three. Three is
                // what fits at the default size, and the row height collapses at the
                // larger Dynamic Type sizes rather than clipping.
                let limit = dynamicTypeSize.isAccessibilitySize ? 2 : 3
                let rows = entry.snapshot.topItems(limit: limit)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows) { item in
                        row(item)
                    }
                }
                Spacer(minLength: 0)
                if let more = WidgetCopy.moreLine(entry.snapshot.hiddenCount(limit: limit)) {
                    Text(more)
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// One medium row: priority mark, kind glyph, title, due hint. The whole row
    /// deep-links to the item, per #29.
    private func row(_ item: WidgetItem) -> some View {
        Link(destination: URL(string: "pulse://item/\(item.id)") ?? URL(string: "pulse://board")!) {
            HStack(spacing: 6) {
                // Shape, not colour: filled for high priority, hollow otherwise, so it
                // still reads when the system desaturates the widget.
                Circle()
                    .strokeBorder(.secondary, lineWidth: WidgetTheme.dotFilled(for: item.priority) ? 0 : 1)
                    .background(Circle().fill(WidgetTheme.dotFilled(for: item.priority) ? Color.primary : Color.clear))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Image(systemName: WidgetTheme.glyph(forKind: item.kind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                Text(item.title)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if let due = item.due {
                    Text(WidgetCopy.dueHint(due, now: entry.date))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: item))
    }

    // MARK: Shared

    /// The one empty state (§9.2 rule: no fabricated data).
    private func emptyState(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: WidgetCopy.emptyGlyph)
                .font(compact ? .footnote : .body)
                .foregroundStyle(.secondary)
            Text(WidgetCopy.emptyTitle)
                .font(compact ? .footnote : .body)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func accessibilityLabel(for item: WidgetItem) -> String {
        var parts = [item.title]
        if let kind = Kind(rawValue: item.kind) {
            parts.append(WidgetTheme.spokenLabel(forKind: item.kind))
        }
        if let due = item.due {
            parts.append(WidgetCopy.dueHint(due, now: entry.date) == "overdue"
                        ? "overdue"
                        : "due " + WidgetCopy.dueHint(due, now: entry.date))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Widget descriptor

struct PulseHomeWidget: Widget {
    /// Stable across releases: the user's Home Screen layout keys off it.
    static let kind = "PulseHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PulseProvider()) { entry in
            PulseHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Pulse Now")
        .description("What needs you right now.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Small", as: .systemSmall) {
    PulseHomeWidget()
} timeline: {
    PulseEntry(date: .now, snapshot: .sample, isPlaceholder: false)
    PulseEntry(date: .now, snapshot: WidgetSnapshot(), isPlaceholder: false)
    PulseEntry.placeholder()
}

#Preview("Medium", as: .systemMedium) {
    PulseHomeWidget()
} timeline: {
    PulseEntry(date: .now, snapshot: .sample, isPlaceholder: false)
    PulseEntry(date: .now, snapshot: WidgetSnapshot(), isPlaceholder: false)
    PulseEntry.placeholder()
}
#endif
