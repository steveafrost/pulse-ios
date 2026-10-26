import SwiftUI

// MARK: - Glass style

/// §6: there are six glass surfaces and no seventh. This modifier is the single
/// place that calls `.glassEffect()`, so the Reduce Transparency substitution
/// (§6.5) cannot be forgotten at a call site.
///
/// Deployment target is iOS 18, so every Liquid Glass call sits inside an
/// `if #available(iOS 26.0, *)` and the else-branch is a material that is
/// visually close enough to ship: same shape, same padding, same border weight.
public struct ThirdHandGlassStyle: ViewModifier {
    public enum Variant: Sendable {
        /// Filter chips, capture capsule at rest, sheets.
        case regular
        /// The FAB and any other obviously tappable chrome.
        case interactive
        /// The Now tint while capturing or while an error pends (§6.1).
        case tintedUrgent
        /// A *selected* chip. Added in the craft pass: selection used to borrow
        /// `.tintedUrgent`, so the unremarkable act of showing "All" painted a pink
        /// pill across the top of the board and spent the red that Now needs. A
        /// selection is a state, not an alarm, so it tints to the foreground colour
        /// instead: clearly chosen, never shouting.
        case selected
    }

    public enum Shape: Sendable {
        case capsule
        case rounded(CGFloat)
    }

    let variant: Variant
    let shape: Shape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public func body(content: Content) -> some View {
        if reduceTransparency {
            // §6.5: solid surface plus a hairline, never glass.
            content
                .background(ThirdHandColor.surfaceCard, in: anyShape)
                .overlay {
                    anyShape.stroke(
                        ThirdHandColor.separator.opacity(ThirdHandContrast(colorSchemeContrast: contrast).separatorOpacity),
                        lineWidth: ThirdHandMetrics.hairline
                    )
                }
        } else {
            glass(content)
        }
    }

    /// No availability branch: the deployment target is iOS 26, so the glass effect
    /// is always present. The app-wide floor was raised deliberately (see
    /// `project.yml`) because placement uses the system language model, which does
    /// not exist below 26.
    private func glass(_ content: Content) -> some View {
        switch variant {
        case .regular:
            content.glassEffect(.regular, in: anyShape)
        case .interactive:
            content.glassEffect(.regular.interactive(), in: anyShape)
        case .tintedUrgent:
            content.glassEffect(.regular.tint(ThirdHandColor.horizonNow.opacity(0.15)), in: anyShape)
        case .selected:
            content.glassEffect(.regular.tint(ThirdHandColor.textPrimary.opacity(0.10)).interactive(), in: anyShape)
        }
    }

    private var anyShape: AnyShape {
        switch shape {
        case .capsule: AnyShape(Capsule())
        case .rounded(let radius): AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

extension View {
    /// The one glass entry point. `variant` picks the interaction/tint behaviour,
    /// `shape` picks the clip.
    public func pulseGlass(_ variant: ThirdHandGlassStyle.Variant = .regular, in shape: ThirdHandGlassStyle.Shape = .capsule) -> some View {
        modifier(ThirdHandGlassStyle(variant: variant, shape: shape))
    }

    /// A glass cluster (§6.3): one container, never nested.
    public func thirdHandGlassContainer(spacing: CGFloat = 8) -> some View {
        GlassEffectContainer(spacing: spacing) { self }
    }
}

// MARK: - Prominent button style

/// §6.1: `glassProminent` for the single primary action per screen; §6.5 keeps
/// the same tint with `.borderedProminent` when transparency is reduced, and the
/// iOS 18 path uses `.borderedProminent` outright.
public struct ThirdHandProminentButtonStyle: ButtonStyle {
    let tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Added in the craft pass. The style used to ignore `isEnabled`, so a primary
    /// action that was correctly `.disabled(...)` — "Connect" with no address yet —
    /// still rendered as fully saturated red. A disabled control that looks enabled
    /// is the same class of dishonesty as a source that fails silently: the user
    /// taps it, nothing happens, and the screen never said why.
    @Environment(\.isEnabled) private var isEnabled

    public init(tint: Color = ThirdHandColor.horizonNow) {
        self.tint = tint
    }

    /// A disabled primary action drops its fill to the neutral pressed surface and
    /// its label to `textTertiary` — clearly present, clearly not available. It keeps
    /// its 44pt frame so the layout does not jump when the form becomes valid.
    private var fill: Color { isEnabled ? tint : ThirdHandColor.surfaceCardPressed }
    private var labelColor: Color { isEnabled ? ThirdHandColor.textOnAccent : ThirdHandColor.textTertiary }

    public func makeBody(configuration: Configuration) -> some View {
        if !reduceTransparency {
            configuration.label
                .font(ThirdHandTypography.buttonLabel)
                .foregroundStyle(labelColor)
                .padding(.horizontal, ThirdHandSpacing.l)
                .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                .glassEffect(isEnabled ? .regular.tint(tint).interactive() : .regular, in: .capsule)
                .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
        } else {
            configuration.label
                .font(ThirdHandTypography.buttonLabel)
                .foregroundStyle(labelColor)
                .padding(.horizontal, ThirdHandSpacing.l)
                .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                .background(fill, in: Capsule())
                .overlay {
                    if !isEnabled {
                        Capsule().strokeBorder(ThirdHandColor.separator, lineWidth: ThirdHandMetrics.hairline)
                    }
                }
                .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
        }
    }
}

extension ButtonStyle where Self == ThirdHandProminentButtonStyle {
    public static func pulseProminent(tint: Color = ThirdHandColor.horizonNow) -> ThirdHandProminentButtonStyle {
        ThirdHandProminentButtonStyle(tint: tint)
    }
}

// MARK: - Sheet chrome

extension View {
    /// §6.1: sheet backing is material, never glass, and it is 28pt at the top
    /// per §4.
    public func pulseSheetChrome() -> some View {
        self
            .presentationBackground(.regularMaterial)
            .presentationCornerRadius(ThirdHandRadius.sheetTop)
            .presentationDragIndicator(.visible)
    }
}
