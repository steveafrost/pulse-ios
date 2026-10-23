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
        VStack(alignment: .leading, spacing: PulseSpacing.s) {
            ForEach(failures) { failure in
                HStack(alignment: .top, spacing: PulseSpacing.s) {
                    Image(systemName: failure.isPermissionProblem ? "calendar.badge.exclamationmark" : "exclamationmark.triangle")
                        .foregroundStyle(PulseColor.statusError)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: PulseSpacing.xxs) {
                        Text(failure.message)
                            .font(PulseTypography.itemDetail)
                            .foregroundStyle(PulseColor.textPrimary)
                        if failure.isPermissionProblem {
                            Button("Open Settings", action: onOpenSettings)
                                .font(PulseTypography.meta)
                                .frame(minHeight: PulseSpacing.minimumHitTarget)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(PulseSpacing.m)
                .background(PulseColor.surfaceCard, in: RoundedRectangle(cornerRadius: PulseRadius.card))
                .accessibilityElement(children: .contain)
            }

            Button("Try again", action: onRetry)
                .buttonStyle(.bordered)
                .frame(minHeight: PulseSpacing.minimumHitTarget)
                .accessibilityIdentifier("board.error.retry")
        }
        .padding(PulseSpacing.screenMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("board.error")
    }
}
