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
        VStack(spacing: PulseSpacing.xl) {
            Spacer(minLength: PulseSpacing.xl)

            Image(systemName: step == .calendar ? "calendar.badge.checkmark" : "checklist")
                .font(.system(size: PulseMetrics.emptyGlyphSize, weight: .light))
                .foregroundStyle(PulseColor.horizonNext)
                .accessibilityHidden(true)

            VStack(spacing: PulseSpacing.xs) {
                Text("Pulse reads your \(step == .calendar ? "calendar" : "reminders") to know what needs you.")
                    .font(PulseTypography.emptyTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PulseColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Everything on device. No account, no server.")
                    .font(PulseTypography.emptyBody)
                    .foregroundStyle(PulseColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: PulseSpacing.xs) {
                bullet("Nothing leaves your device", "lock.fill")
                bullet("No account", "person.crop.circle.badge.xmark")
                bullet("You can revoke any time", "arrow.uturn.backward.circle")
            }
            .frame(maxWidth: 320, alignment: .leading)

            Spacer(minLength: PulseSpacing.m)

            VStack(spacing: PulseSpacing.xs) {
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
                    .foregroundStyle(PulseColor.textSecondary)
                    .frame(minHeight: PulseSpacing.minimumHitTarget)
                    .accessibilityIdentifier("preamble.notNow")
            }
        }
        .padding(PulseSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulseColor.surfaceCanvas)
        .accessibilityIdentifier("preamble.root")
    }

    private func bullet(_ text: String, _ glyph: String) -> some View {
        Label {
            Text(text).font(PulseTypography.itemDetail)
        } icon: {
            Image(systemName: glyph).foregroundStyle(PulseColor.horizonNext)
        }
        .foregroundStyle(PulseColor.textSecondary)
    }
}
