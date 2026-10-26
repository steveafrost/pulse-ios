import SwiftUI

/// §6.1: a filter chip is a glass capsule; all of them live in one
/// `GlassEffectContainer`. §10: ≥44pt hit target, and it grows with Dynamic Type.
public struct ThirdHandCapsuleButton: View {
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
            HStack(spacing: ThirdHandSpacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(ThirdHandTypography.chip)
                    .lineLimit(1)
                if let badge {
                    // §1: "one numeric emphasis per screen — the Now badge". The
                    // badge is that one emphasis, so it stays filled red; the
                    // chip around it does not (see `.pulseGlass` below).
                    Text(badge)
                        .font(ThirdHandTypography.badgeCount)
                        .foregroundStyle(ThirdHandColor.textOnAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(ThirdHandColor.horizonNow, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .font(ThirdHandTypography.chip)
            .foregroundStyle(isSelected ? ThirdHandColor.textPrimary : ThirdHandColor.textSecondary)
            .padding(.horizontal, ThirdHandSpacing.s)
            .padding(.vertical, ThirdHandSpacing.xs)
            .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Selection is a state, not an alarm: `.selected`, never `.tintedUrgent`.
        // The red on the board belongs to Now.
        .pulseGlass(isSelected ? .selected : .regular, in: .capsule)
        // The badge is hidden from VoiceOver on its own, so the count has to
        // ride along here or a chip reads "All" while showing "3".
        .accessibilityLabel(badge.map { "\(title), \(Plural.items(Int($0) ?? 0)) in Now" } ?? title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
