import SwiftUI

/// §8.1: a per-source failure is a row, not a blocker. `SourceBanner` is the thin
/// persistent version; this is the failure list shown when nothing loaded.
public struct ErrorBoardView: View {
    let failures: [SourceFailure]
    var onRetry: () -> Void
    var onOpenSettings: () -> Void

    public init(failures: [SourceFailure], onRetry: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.failures = failures
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.s) {
            ForEach(failures) { failure in
                HStack(alignment: .top, spacing: ThirdHandSpacing.s) {
                    Image(systemName: failure.isPermissionProblem ? "calendar.badge.exclamationmark" : "exclamationmark.triangle")
                        .foregroundStyle(ThirdHandColor.statusError)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: ThirdHandSpacing.xxs) {
                        Text(failure.message)
                            .font(ThirdHandTypography.itemDetail)
                            .foregroundStyle(ThirdHandColor.textPrimary)
                        if failure.isPermissionProblem {
                            Button("Open Settings", action: onOpenSettings)
                                .font(ThirdHandTypography.meta)
                                .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(ThirdHandSpacing.m)
                .background(ThirdHandColor.surfaceCard, in: RoundedRectangle(cornerRadius: ThirdHandRadius.card))
                .accessibilityElement(children: .contain)
            }

            Button("Try again", action: onRetry)
                .buttonStyle(.bordered)
                .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                .accessibilityIdentifier("board.error.retry")
        }
        .padding(ThirdHandSpacing.screenMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("board.error")
    }
}
