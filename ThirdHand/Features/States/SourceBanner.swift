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
        HStack(spacing: ThirdHandSpacing.xs) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(ThirdHandColor.statusError)
                .accessibilityHidden(true)
            Text(failure.message)
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Open Settings", action: onOpenSettings)
                .font(.footnote.weight(.medium))
                .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                .accessibilityIdentifier("banner.openSettings")
        }
        .padding(.horizontal, ThirdHandSpacing.s)
        .padding(.vertical, ThirdHandSpacing.xxs)
        .pulseGlass(.regular, in: .rounded(ThirdHandRadius.card))
        .padding(.horizontal, ThirdHandSpacing.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board.sourceBanner")
    }
}
