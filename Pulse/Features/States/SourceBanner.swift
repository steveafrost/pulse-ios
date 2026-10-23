import SwiftUI

/// §9.3: a denied source is a non-blocking banner when other sources still work.
public struct SourceBanner: View {
    let failure: SourceFailure
    var onOpenSettings: () -> Void

    public init(failure: SourceFailure, onOpenSettings: @escaping () -> Void) {
        self.failure = failure
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        HStack(spacing: PulseSpacing.xs) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(PulseColor.statusError)
                .accessibilityHidden(true)
            Text(failure.message)
                .font(PulseTypography.meta)
                .foregroundStyle(PulseColor.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Settings", action: onOpenSettings)
                .font(.footnote.weight(.medium))
                .frame(minHeight: PulseSpacing.minimumHitTarget)
                .accessibilityIdentifier("banner.openSettings")
        }
        .padding(.horizontal, PulseSpacing.s)
        .padding(.vertical, PulseSpacing.xxs)
        .pulseGlass(.regular, in: .rounded(PulseRadius.card))
        .padding(.horizontal, PulseSpacing.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board.sourceBanner")
    }
}
