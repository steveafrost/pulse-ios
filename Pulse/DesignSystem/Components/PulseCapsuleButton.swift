import SwiftUI

/// §6.1: a filter chip is a glass capsule; all of them live in one
/// `GlassEffectContainer`. §10: ≥44pt hit target, and it grows with Dynamic Type.
public struct PulseCapsuleButton: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let badge: String?
    let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        badge: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.badge = badge
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: PulseSpacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(PulseTypography.chip)
                    .lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(PulseTypography.badgeCount)
                        .foregroundStyle(PulseColor.textOnAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(PulseColor.horizonNow, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? PulseColor.textPrimary : PulseColor.textSecondary)
            .padding(.horizontal, PulseSpacing.s)
            .padding(.vertical, PulseSpacing.xs)
            .frame(minHeight: PulseSpacing.minimumHitTarget)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pulseGlass(isSelected ? .tintedUrgent : .regular, in: .capsule)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
