import SwiftUI

/// §9: three genuinely different empty screens with the exact copy from the
/// spec. One view, three configurations, so the wording cannot drift apart.
public struct EmptyBoardView: View {
    let reason: BoardState.EmptyReason
    let lastCapturedAt: Date?
    let now: Date
    let preferredSource: SourceIdentity
    var onRefresh: () -> Void
    var onConnect: (SourceIdentity) -> Void
    var onNotNow: () -> Void
    var onOpenSettings: () -> Void
    var onResetFilters: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        reason: BoardState.EmptyReason,
        lastCapturedAt: Date? = nil,
        now: Date,
        preferredSource: SourceIdentity = .calendar,
        onRefresh: @escaping () -> Void = {},
        onConnect: @escaping (SourceIdentity) -> Void = { _ in },
        onNotNow: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onResetFilters: @escaping () -> Void = {}
    ) {
        self.reason = reason
        self.lastCapturedAt = lastCapturedAt
        self.now = now
        self.preferredSource = preferredSource
        self.onRefresh = onRefresh
        self.onConnect = onConnect
        self.onNotNow = onNotNow
        self.onOpenSettings = onOpenSettings
        self.onResetFilters = onResetFilters
    }

    public var body: some View {
        VStack(spacing: PulseSpacing.m) {
            Image(systemName: glyph)
                .font(.system(size: PulseMetrics.emptyGlyphSize, weight: .light))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(heading)
                .font(PulseTypography.emptyTitle)
                .foregroundStyle(PulseColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(bodyCopy)
                .font(PulseTypography.emptyBody)
                .foregroundStyle(PulseColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)

            buttons
                .padding(.top, PulseSpacing.xs)

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(PulseColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PulseSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board.empty.\(identifier)")
    }

    private var identifier: String {
        switch reason {
        case .allClear: "allClear"
        case .neverCaptured: "neverCaptured"
        case .filtered: "filtered"
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch reason {
        case .allClear:
            Button("Refresh", action: onRefresh)
                .buttonStyle(.bordered)
                .frame(minHeight: PulseSpacing.minimumHitTarget)
                .accessibilityIdentifier("board.empty.refresh")
        case .neverCaptured:
            VStack(spacing: PulseSpacing.xs) {
                Button("Connect \(preferredSource.title)") { onConnect(preferredSource) }
                    .buttonStyle(.pulseProminent())
                    .accessibilityIdentifier("board.empty.connect")
                Button("Not now", action: onNotNow)
                    .buttonStyle(.plain)
                    .foregroundStyle(PulseColor.textSecondary)
                    .frame(minHeight: PulseSpacing.minimumHitTarget)
            }
        case .filtered:
            Button("Reset filters", action: onResetFilters)
                .buttonStyle(.bordered)
                .frame(minHeight: PulseSpacing.minimumHitTarget)
                .accessibilityIdentifier("board.empty.reset")
        }
    }

    private var glyph: String {
        switch reason {
        case .allClear: "checkmark.circle.fill"
        case .neverCaptured: "sparkles"
        case .filtered: "line.3.horizontal.decrease.circle"
        }
    }

    private var tint: Color {
        switch reason {
        case .allClear: PulseColor.statusDone
        case .neverCaptured: PulseColor.horizonNow
        case .filtered: PulseColor.textTertiary
        }
    }

    /// §9 copy, verbatim.
    private var heading: String {
        switch reason {
        case .allClear: "You're all clear"
        case .neverCaptured: "Let's see what needs you"
        case .filtered: "Nothing matches this filter"
        }
    }

    private var bodyCopy: String {
        switch reason {
        case .allClear:
            "Nothing needs you right now. Pulse is watching your calendar and reminders and will put the next thing here."
        case .neverCaptured:
            "Connect your calendar and reminders. Pulse reads them on this device and never sends anything anywhere."
        case .filtered:
            "Every item is filtered out. Clear the filter to see the whole board."
        }
    }

    private var footnote: String {
        switch reason {
        case .allClear:
            if let lastCapturedAt {
                return "Last checked \(PulseDateFormat.relative(lastCapturedAt, now: now))"
            }
            return "Not checked yet"
        case .neverCaptured:
            return "You can turn sources on or off later in Settings."
        case .filtered:
            return "Filters are never saved between launches."
        }
    }
}
