import SwiftUI
import ThirdHandCore

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
        VStack(alignment: .leading, spacing: ThirdHandSpacing.s) {
            Text("History")
                .font(ThirdHandTypography.eyebrow)
                .foregroundStyle(ThirdHandColor.textTertiary)
                .accessibilityAddTraits(.isHeader)

            let shown = showsAll ? entries : Array(entries.prefix(visibleLimit))
            ForEach(Array(shown.enumerated()), id: \.offset) { _, entry in
                row(entry)
            }

            if entries.count > visibleLimit, !showsAll {
                Button("Show older") { withAnimation { showsAll = true } }
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(ThirdHandColor.horizonNext)
                    .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(BoardCopy.history(entries.count))
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: ThirdHandSpacing.xs) {
            Circle()
                .fill(ThirdHandColor.separator)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: ThirdHandSpacing.xxs) {
                    Text(HistoryCopy.change(entry.change))
                        .font(ThirdHandTypography.itemDetail)
                        .foregroundStyle(ThirdHandColor.textPrimary)
                    Text(HistoryCopy.actor(entry.by))
                        .font(ThirdHandTypography.chip)
                        .foregroundStyle(ThirdHandColor.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            ThirdHandColor.separator.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: ThirdHandRadius.chip)
                        )
                }
                Text(summary(entry))
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(ThirdHandColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(ThirdHandDateFormat.relative(entry.at, now: now))
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(entry))
    }

    private func summary(_ entry: HistoryEntry) -> String {
        var parts: [String] = []
        if let reason = entry.reason, !reason.isEmpty {
            parts.append(reason)
        }
        if let until = entry.until {
            parts.append(ThirdHandDateFormat.snoozeUntil(until))
        }
        return parts.joined(separator: " · ")
    }

    private func spoken(_ entry: HistoryEntry) -> String {
        var parts =
            [
                "\(HistoryCopy.change(entry.change)), by \(HistoryCopy.actorSpoken(entry.by)), \(ThirdHandDateFormat.relative(entry.at, now: now))"
            ]
        if let reason = entry.reason, !reason.isEmpty {
            parts.append(reason)
        }
        if let until = entry.until {
            parts.append("until \(ThirdHandDateFormat.snoozeUntil(until))")
        }
        return parts.joined(separator: ", ")
    }
}

/// §18: history is store vocabulary (`change` is a status or a comma-joined field
/// list, `by` is the writer id "capture" / "user" / "mirror"). Both are rendered
/// for a person: a verb phrase and who did it, never the raw token.
///
/// The store strings are load-bearing (the Mac mirror greps them), so the mapping
/// lives here rather than in `ThirdHandCore`: the wire keeps its tokens, the screen
/// keeps its sentences, and an unknown token falls back to itself instead of
/// going blank.
public enum HistoryCopy {
    public static func change(_ raw: String) -> String {
        switch raw {
        case "created": return "Added"
        case "done": return "Marked done"
        case "dismissed": return "Dismissed"
        case "snoozed": return "Snoozed"
        case "open": return "Reopened"
        case "resolved": return "Resolved"
        case "waiting": return "Set to waiting"
        case "snooze-expired": return "Snooze ended"
        default:
            // A capture delta is a comma-joined field list ("title,detail").
            if raw.contains(",") {
                return "Updated " + raw.split(separator: ",").joined(separator: ", ")
            }
            return raw.replacingOccurrences(of: "-", with: " ").capitalizedFirst
        }
    }

    /// "You", "Pulse", "Your Mac" — the three writers a person can name.
    public static func actor(_ raw: String) -> String {
        switch raw {
        case "user": "You"
        case "capture": "Pulse"
        case "mirror": "Your Mac"
        default: raw.replacingOccurrences(of: "-", with: " ").capitalizedFirst
        }
    }

    /// The same actor as a phrase, for the composed VoiceOver sentence.
    public static func actorSpoken(_ raw: String) -> String {
        raw == "user" ? "you" : actor(raw)
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
