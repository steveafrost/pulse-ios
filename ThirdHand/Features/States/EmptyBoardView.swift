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
        VStack(spacing: ThirdHandSpacing.m) {
            Image(systemName: glyph)
                .font(.system(size: ThirdHandMetrics.emptyGlyphSize, weight: .light))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(heading)
                .font(ThirdHandTypography.emptyTitle)
                .foregroundStyle(ThirdHandColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(bodyCopy)
                .font(ThirdHandTypography.emptyBody)
                .foregroundStyle(ThirdHandColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)

            buttons
                .padding(.top, ThirdHandSpacing.xs)

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(ThirdHandColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ThirdHandSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board.empty.\(identifier)")
    }

    private var identifier: String {
        switch reason {
        case .allClear: "allClear"
        case .neverCaptured: "neverCaptured"
        case .filtered: "filtered"
        case .denied(let identity): "denied.\(identity.rawValue)"
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch reason {
        case .allClear:
            Button("Refresh", action: onRefresh)
                .buttonStyle(.bordered)
                .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                .accessibilityIdentifier("board.empty.refresh")
        case .neverCaptured:
            VStack(spacing: ThirdHandSpacing.xs) {
                Button("Connect \(preferredSource.title)") { onConnect(preferredSource) }
                    .buttonStyle(.pulseProminent())
                    .accessibilityIdentifier("board.empty.connect")
                Button("Not now", action: onNotNow)
                    .buttonStyle(.plain)
                    .foregroundStyle(ThirdHandColor.textSecondary)
                    .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
            }
        case .filtered:
            Button("Reset filters", action: onResetFilters)
                .buttonStyle(.bordered)
                .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                .accessibilityIdentifier("board.empty.reset")
        case .denied(let identity):
            // §9.3: Open Settings is the way back; "Choose sources" re-runs the
            // preamble instead of refusing outright, which is what "Not now" in
            // 9.2 left the board able to do.
            //
            // A paused *mailbox* is the one case where iOS Settings has nothing to
            // turn on: there is no mail row there at all. The caller routes its
            // button to the mailbox form, so the label says what the button does.
            VStack(spacing: ThirdHandSpacing.xs) {
                Button(identity == .email ? "Connect a mailbox" : "Open Settings", action: onOpenSettings)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("board.empty.openSettings")
                // "Choose sources" re-runs the EventKit preamble. Mail has no
                // permission to re-ask for, so the button would be a second dead end
                // on the same screen -- the mailbox form above is the whole fix.
                if identity != .email {
                    Button("Choose sources") { onConnect(identity) }
                        .buttonStyle(.plain)
                        .foregroundStyle(ThirdHandColor.textSecondary)
                        .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                        .accessibilityIdentifier("board.empty.chooseSources")
                }
            }
        }
    }

    private var glyph: String {
        switch reason {
        case .allClear: "checkmark.circle.fill"
        case .neverCaptured: "sparkles"
        case .filtered: "line.3.horizontal.decrease.circle"
        case .denied: "calendar.badge.exclamationmark"
        }
    }

    private var tint: Color {
        switch reason {
        case .allClear: ThirdHandColor.statusDone
        case .neverCaptured: ThirdHandColor.horizonNow
        case .filtered: ThirdHandColor.textTertiary
        case .denied: ThirdHandColor.statusError
        }
    }

    /// §9 copy, verbatim.
    private var heading: String {
        switch reason {
        case .allClear: "You're all clear"
        case .neverCaptured: "Let's see what needs you"
        case .filtered: "Nothing matches this filter"
        case .denied(let identity): "Pulse can't see your \(identity.title.lowercased())"
        }
    }

    private var bodyCopy: String {
        switch reason {
        case .allClear:
            "Nothing needs you right now. Pulse is watching your calendar and reminders, and you can share a Slack thread, a pull request, or an email here to add it."
        case .neverCaptured:
            "Connect your calendar and reminders, or share a link into Pulse. Everything is read on this device and never sent anywhere."
        case .filtered:
            "Every item is filtered out. Clear the filter to see the whole board."
        case .denied(let identity):
            // Mail is not a permission and cannot be turned on in iOS Settings -- it is
            // an account the user has to add, with an app password, on a screen this
            // app provides. Sending them to iOS Settings to look for a mailbox toggle
            // is the dead end that made email look broken.
            if identity == .email {
                "No mailbox is connected, so there is no mail to read. Add one and Pulse will put the messages that need you on this board."
            } else {
                "\(identity.title) access is off. Turn it on in Settings and Pulse will fill this board."
            }
        }
    }

    private var footnote: String {
        switch reason {
        case .allClear:
            if let lastCapturedAt {
                return "Last checked \(ThirdHandDateFormat.relative(lastCapturedAt, now: now))"
            }
            return "Not checked yet"
        case .neverCaptured:
            return "You can turn sources on or off later in Settings."
        case .filtered:
            return "Filters are never saved between launches."
        case .denied:
            // Was "Nothing leaves it", which a connected mailbox makes false --
            // the password goes to the user's own mail server. Scope the claim to
            // what this state is actually about: the calendar and reminders.
            return "Pulse reads your calendar and reminders on this device."
        }
    }
}
