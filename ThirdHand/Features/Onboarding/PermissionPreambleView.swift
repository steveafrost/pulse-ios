import SwiftUI

/// §8.3 `PermissionPrimerView`: the explainer before the system prompt (#20).
/// Two steps, one rationale, `Continue` then the real request.
public struct PermissionPreambleView: View {
    var onAllow: (SourceIdentity) -> Void
    var onNotNow: () -> Void

    @State private var step: Step = .calendar

    public enum Step: Int, CaseIterable {
        case calendar, reminders
    }

    public init(onAllow: @escaping (SourceIdentity) -> Void, onNotNow: @escaping () -> Void) {
        self.onAllow = onAllow
        self.onNotNow = onNotNow
    }

    public var body: some View {
        VStack(spacing: ThirdHandSpacing.xl) {
            Spacer(minLength: ThirdHandSpacing.xl)

            Image(systemName: step == .calendar ? "calendar.badge.checkmark" : "checklist")
                .font(.system(size: ThirdHandMetrics.emptyGlyphSize, weight: .light))
                .foregroundStyle(ThirdHandColor.horizonNext)
                .accessibilityHidden(true)

            VStack(spacing: ThirdHandSpacing.xs) {
                Text("Third Hand reads your \(step == .calendar ? "calendar" : "reminders") to know what needs you.")
                    .font(ThirdHandTypography.emptyTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ThirdHandColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Everything on device. No account, no server.")
                    .font(ThirdHandTypography.emptyBody)
                    .foregroundStyle(ThirdHandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
                // Scoped to the sources being asked about. A blanket "nothing leaves
                // your device" stopped being true once an optional mailbox existed;
                // this screen only ever precedes the calendar/reminders prompt.
                bullet("Calendar and reminders never leave your device", "lock.fill")
                bullet("No account", "person.crop.circle.badge.xmark")
                bullet("You can revoke any time", "arrow.uturn.backward.circle")
            }
            .frame(maxWidth: 320, alignment: .leading)

            Spacer(minLength: ThirdHandSpacing.m)

            VStack(spacing: ThirdHandSpacing.xs) {
                Button(step == .calendar ? "Continue" : "Connect Reminders") {
                    onAllow(step == .calendar ? .calendar : .reminders)
                    if let next = Step(rawValue: step.rawValue + 1) {
                        step = next
                    }
                }
                .buttonStyle(.pulseProminent())
                .frame(maxWidth: 320)
                .accessibilityIdentifier("preamble.continue")

                Button("Not now", action: onNotNow)
                    .buttonStyle(.plain)
                    .foregroundStyle(ThirdHandColor.textSecondary)
                    .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                    .accessibilityIdentifier("preamble.notNow")
            }
        }
        .padding(ThirdHandSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThirdHandColor.surfaceCanvas)
        .accessibilityIdentifier("preamble.root")
    }

    private func bullet(_ text: String, _ glyph: String) -> some View {
        Label {
            Text(text).font(ThirdHandTypography.itemDetail)
        } icon: {
            Image(systemName: glyph).foregroundStyle(ThirdHandColor.horizonNext)
        }
        .foregroundStyle(ThirdHandColor.textSecondary)
    }
}
