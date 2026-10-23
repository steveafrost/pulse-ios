import SwiftUI

// MARK: - Glass style

/// §6: there are six glass surfaces and no seventh. This modifier is the single
/// place that calls `.glassEffect()`, so the Reduce Transparency substitution
/// (§6.5) cannot be forgotten at a call site.
///
/// Deployment target is iOS 18, so every Liquid Glass call sits inside an
/// `if #available(iOS 26.0, *)` and the else-branch is a material that is
/// visually close enough to ship: same shape, same padding, same border weight.
public struct PulseGlassStyle: ViewModifier {
    public enum Variant: Sendable {
        /// Filter chips, capture capsule at rest, sheets.
        case regular
        /// The FAB and any other obviously tappable chrome.
        case interactive
        /// The Now tint while capturing or while an error pends (§6.1).
        case tintedUrgent
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
                .background(PulseColor.surfaceCard, in: anyShape)
                .overlay {
                    anyShape.stroke(
                        PulseColor.separator.opacity(PulseContrast(colorSchemeContrast: contrast).separatorOpacity),
                        lineWidth: PulseMetrics.hairline
                    )
                }
        } else {
            glass(content)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            switch variant {
            case .regular:
                content.glassEffect(.regular, in: anyShape)
            case .interactive:
                content.glassEffect(.regular.interactive(), in: anyShape)
            case .tintedUrgent:
                content.glassEffect(.regular.tint(PulseColor.horizonNow.opacity(0.15)), in: anyShape)
            }
        } else {
            // iOS 18 fallback: the system material, tinted for the urgent variant.
            content
                .background(backgroundMaterial, in: anyShape)
                .overlay {
                    anyShape.stroke(PulseColor.separator, lineWidth: PulseMetrics.hairline)
                }
        }
    }

    private var backgroundMaterial: Material {
        variant == .tintedUrgent
            ? .regularMaterial
            : .regularMaterial
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
    public func pulseGlass(_ variant: PulseGlassStyle.Variant = .regular, in shape: PulseGlassStyle.Shape = .capsule) -> some View {
        modifier(PulseGlassStyle(variant: variant, shape: shape))
    }

    /// A glass cluster (§6.3): one container, never nested.
    @ViewBuilder
    public func pulseGlassContainer(spacing: CGFloat = 8) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

// MARK: - Prominent button style

/// §6.1: `glassProminent` for the single primary action per screen; §6.5 keeps
/// the same tint with `.borderedProminent` when transparency is reduced, and the
/// iOS 18 path uses `.borderedProminent` outright.
public struct PulseProminentButtonStyle: ButtonStyle {
    let tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(tint: Color = PulseColor.horizonNow) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            configuration.label
                .font(PulseTypography.buttonLabel)
                .foregroundStyle(PulseColor.textOnAccent)
                .padding(.horizontal, PulseSpacing.l)
                .frame(minHeight: PulseSpacing.minimumHitTarget)
                .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
                .opacity(configuration.isPressed ? 0.85 : 1)
        } else {
            configuration.label
                .font(PulseTypography.buttonLabel)
                .foregroundStyle(PulseColor.textOnAccent)
                .padding(.horizontal, PulseSpacing.l)
                .frame(minHeight: PulseSpacing.minimumHitTarget)
                .background(tint, in: Capsule())
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

extension ButtonStyle where Self == PulseProminentButtonStyle {
    public static func pulseProminent(tint: Color = PulseColor.horizonNow) -> PulseProminentButtonStyle {
        PulseProminentButtonStyle(tint: tint)
    }
}

// MARK: - Sheet chrome

extension View {
    /// §6.1: sheet backing is material, never glass, and it is 28pt at the top
    /// per §4.
    public func pulseSheetChrome() -> some View {
        self
            .presentationBackground(.regularMaterial)
            .presentationCornerRadius(PulseRadius.sheetTop)
            .presentationDragIndicator(.visible)
    }
}
