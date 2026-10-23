import PulseCore
import SwiftUI

/// §18: history newest first, relative timestamps, `by` as a compact badge,
/// capped at 20 with "Show older".
public struct HistoryTimeline: View {
    let entries: [HistoryEntry]
    let now: Date

    @State private var showsAll = false
    private let visibleLimit = 20

    public init(entries: [HistoryEntry], now: Date) {
        self.entries = entries
        self.now = now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.s) {
            Text("History")
                .font(PulseTypography.eyebrow)
                .foregroundStyle(PulseColor.textTertiary)
                .accessibilityAddTraits(.isHeader)

            let shown = showsAll ? entries : Array(entries.prefix(visibleLimit))
            ForEach(Array(shown.enumerated()), id: \.offset) { _, entry in
                row(entry)
            }

            if entries.count > visibleLimit, !showsAll {
                Button("Show older") { withAnimation { showsAll = true } }
                    .font(PulseTypography.meta)
                    .foregroundStyle(PulseColor.horizonNext)
                    .frame(minHeight: PulseSpacing.minimumHitTarget)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History, \(entries.count) entries")
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: PulseSpacing.xs) {
            Circle()
                .fill(PulseColor.separator)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: PulseSpacing.xxs) {
                    Text(entry.change)
                        .font(PulseTypography.itemDetail)
                        .foregroundStyle(PulseColor.textPrimary)
                    Text(entry.by)
                        .font(PulseTypography.chip)
                        .foregroundStyle(PulseColor.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PulseColor.separator.opacity(0.3), in: RoundedRectangle(cornerRadius: PulseRadius.chip))
                }
                Text(summary(entry))
                    .font(PulseTypography.meta)
                    .foregroundStyle(PulseColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(PulseDateFormat.relative(entry.at, now: now))
                .font(PulseTypography.meta)
                .foregroundStyle(PulseColor.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(entry))
    }

    private func summary(_ entry: HistoryEntry) -> String {
        var parts: [String] = []
        if let reason = entry.reason, !reason.isEmpty { parts.append(reason) }
        if let until = entry.until { parts.append(PulseDateFormat.snoozeUntil(until)) }
        return parts.joined(separator: " · ")
    }

    private func spoken(_ entry: HistoryEntry) -> String {
        var parts = ["\(entry.change), by \(entry.by), \(PulseDateFormat.relative(entry.at, now: now))"]
        if let reason = entry.reason, !reason.isEmpty { parts.append(reason) }
        if let until = entry.until { parts.append("until \(PulseDateFormat.snoozeUntil(until))") }
        return parts.joined(separator: ", ")
    }
}
