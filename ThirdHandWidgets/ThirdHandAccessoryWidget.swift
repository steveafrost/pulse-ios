import ThirdHandCore
import SwiftUI
import WidgetKit

/// The Lock Screen accessory widget (issue #30): circular gauge, rectangular top
/// item, inline one-liner.
///
/// The Lock Screen desaturates and can render monochrome, so nothing here depends on
/// a hue surviving: the gauge is the system's, the text is `.primary`/`.secondary`,
/// and `AccessoryWidgetBackground()` supplies the platter in tinted and full-colour
/// modes alike. The issue's "tint by urgency" is expressed as *shape and weight*
/// (a filled gauge vs an empty one with a checkmark, semibold vs regular) which is
/// what stays legible when the system strips the colour out.
struct ThirdHandAccessoryWidgetView: View {
    let entry: ThirdHandEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: circular
        }
    }

    // MARK: Circular

    /// `Gauge(.accessoryCircularCapacity)` with the count centred. The cap is
    /// `WidgetCopy.circularMax` (9): past it the numeral reads "10+", which is what
    /// keeps a twelve-item board from overflowing the ring (#30's acceptance).
    private var circular: some View {
        Gauge(value: min(Double(entry.snapshot.nowCount), Double(WidgetCopy.circularMax)),
              in: 0...Double(WidgetCopy.circularMax)) {
            EmptyView()
        } currentValueLabel: {
            if entry.snapshot.isEmpty {
                Image(systemName: "checkmark")
                    .font(.system(.title3, weight: .semibold))
            } else {
                Text(WidgetCopy.circularValue(entry.snapshot.nowCount))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.7)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(.primary)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.countAccessibilityLabel(entry.snapshot.nowCount))
    }

    // MARK: Rectangular

    /// The single most urgent item over two lines, then the due hint and "+N more".
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(WidgetCopy.rectangularTitle(entry.snapshot))
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .widgetAccentable()

            Text(WidgetCopy.rectangularDetail(entry.snapshot, now: entry.date))
                .font(.system(.caption2, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rectangularAccessibilityLabel)
    }

    private var rectangularAccessibilityLabel: String {
        guard let top = entry.snapshot.topItem else {
            return WidgetCopy.countAccessibilityLabel(0)
        }
        var parts = [WidgetCopy.countAccessibilityLabel(entry.snapshot.nowCount), top.title]
        if let due = top.due { parts.append("due " + WidgetCopy.dueHint(due, now: entry.date)) }
        let hidden = entry.snapshot.hiddenCount(limit: 1)
        if hidden > 0 { parts.append("and \(hidden) more") }
        return parts.joined(separator: ", ")
    }

    // MARK: Inline

    /// One line, truncated by `WidgetCopy` before the system ever sees it: the
    /// accessoryInline budget is roughly 30 characters and the system cuts
    /// mid-word, so the title is trimmed at a word boundary first (#30).
    private var inline: some View {
        Text(WidgetCopy.inlineLine(entry.snapshot))
            .accessibilityLabel(WidgetCopy.countAccessibilityLabel(entry.snapshot.nowCount))
    }
}

// MARK: - Widget descriptor

struct ThirdHandAccessoryWidget: Widget {
    static let kind = "ThirdHandAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ThirdHandProvider()) { entry in
            ThirdHandAccessoryWidgetView(entry: entry)
        }
        .configurationDisplayName("Pulse")
        .description("What needs you, on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Circular", as: .accessoryCircular) {
    ThirdHandAccessoryWidget()
} timeline: {
    ThirdHandEntry(date: .now, snapshot: .sample, isPlaceholder: false)
    ThirdHandEntry(date: .now, snapshot: .sampleOverflowing, isPlaceholder: false)
    ThirdHandEntry(date: .now, snapshot: WidgetSnapshot(), isPlaceholder: false)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    ThirdHandAccessoryWidget()
} timeline: {
    ThirdHandEntry(date: .now, snapshot: .sample, isPlaceholder: false)
    ThirdHandEntry(date: .now, snapshot: .sampleLongTitle, isPlaceholder: false)
    ThirdHandEntry(date: .now, snapshot: WidgetSnapshot(), isPlaceholder: false)
}

#Preview("Inline", as: .accessoryInline) {
    ThirdHandAccessoryWidget()
} timeline: {
    ThirdHandEntry(date: .now, snapshot: .sample, isPlaceholder: false)
    ThirdHandEntry(date: .now, snapshot: .sampleLongTitle, isPlaceholder: false)
    ThirdHandEntry(date: .now, snapshot: WidgetSnapshot(), isPlaceholder: false)
}
#endif
