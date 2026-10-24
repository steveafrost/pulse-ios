import SwiftUI

// MARK: - Colour

/// The single source of truth for colour. Token name == asset-catalogue colour set
/// name (`docs/DESIGN.md` §2), so a token here can always be traced to a row in
/// that table. Views never write a hex literal or `Color(red:green:blue:)`.
///
/// The contrast rules (§2, non-negotiable rules 2 and 3) are applied in
/// `ThirdHandContrast`, which the components consult for the `@70%`/`@12%` collapses
/// when Increased Contrast is on.
public enum ThirdHandColor {
    // Text hierarchy
    public static let textPrimary = Color("TextPrimary")
    public static let textSecondary = Color("TextSecondary")
    public static let textTertiary = Color("TextTertiary")
    public static let textOnAccent = Color("TextOnAccent")

    // Surfaces
    public static let surfaceCanvas = Color("SurfaceCanvas")
    public static let surfaceCard = Color("SurfaceCard")
    public static let surfaceCardPressed = Color("SurfaceCardPressed")
    public static let separator = Color("Separator")

    // Horizon tints
    public static let horizonNow = Color("HorizonNow")
    public static let horizonNext = Color("HorizonNext")
    public static let horizonLater = Color("HorizonLater")
    public static let horizonFYI = Color("HorizonFYI")

    // Source identity
    public static let sourceCalendar = Color("SourceCalendar")
    public static let sourceReminders = Color("SourceReminders")
    public static let sourceGmail = Color("SourceGmail")
    public static let sourceSlack = Color("SourceSlack")
    public static let sourceOther = Color("SourceOther")

    // Kind and status
    public static let kindNeutral = Color("KindNeutral")
    public static let kindAttention = Color("KindAttention")
    public static let kindDeadline = Color("KindDeadline")
    public static let statusWaiting = Color("StatusWaiting")
    public static let statusSnoozed = Color("StatusSnoozed")
    public static let statusDone = Color("StatusDone")
    public static let statusError = Color("StatusError")

    public static let accent = Color("AccentColor")
}

// MARK: - Spacing
//
// §4: only these eight values exist. Anything else is a bug, not a preference.
public enum ThirdHandSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48

    /// Screen margin, added to the safe area rather than replacing it.
    public static let screenMargin: CGFloat = 16
    /// §4: an 8pt gap between cards *is* the separator.
    public static let cardGap: CGFloat = 8
    /// Board bottom inset above the FAB.
    public static let boardBottomInset: CGFloat = 48
    /// §10 hit-target floor.
    public static let minimumHitTarget: CGFloat = 44
    /// Max content width on iPad.
    public static let maxContentWidth: CGFloat = 720
    /// Row minima from §4.
    public static let rowTitleMinHeight: CGFloat = 72
    public static let rowTitleDetailMinHeight: CGFloat = 92
    public static let rowFullMinHeight: CGFloat = 112
}

public enum ThirdHandRadius {
    public static let card: CGFloat = 16
    public static let widget: CGFloat = 20
    public static let sheetTop: CGFloat = 28
    public static let chip: CGFloat = 4
    public static let capsule: CGFloat = 999
    public static let rail: CGFloat = 1.5
}

// MARK: - Typography
//
// §3: `.system` text styles only — no fixed point sizes anywhere, because a fixed
// size breaks Dynamic Type. Weight is the only axis besides style.

public enum ThirdHandTypography {
    /// "Third Hand", inline at rest.
    public static let boardTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    public static let sectionHeader = Font.system(.title3, weight: .semibold)
    public static let sectionHint = Font.system(.footnote, weight: .regular)
    public static let itemTitle = Font.system(.headline, weight: .semibold)
    public static let itemDetail = Font.system(.subheadline, weight: .regular)
    public static let meta = Font.system(.footnote, weight: .regular)
    public static let chip = Font.system(.caption2, weight: .medium)
    public static let badgeCount = Font.system(.caption, design: .rounded, weight: .bold)
    public static let buttonLabel = Font.system(.body, weight: .semibold)
    public static let captureCapsule = Font.system(.footnote, weight: .medium)
    public static let emptyTitle = Font.system(.title2, weight: .semibold)
    public static let emptyBody = Font.system(.body, weight: .regular)
    public static let eyebrow = Font.system(.caption2, weight: .semibold)
}

// MARK: - Rails and hairlines

public enum ThirdHandMetrics {
    public static let railWidth: CGFloat = 3
    public static let hairline: CGFloat = 1
    public static let kindGlyphSize: CGFloat = 20
    public static let newnessDot: CGFloat = 6
    public static let emptyGlyphSize: CGFloat = 64
    /// The board row's meta strip height, so the horizontal scroller has a
    /// definite height inside a `VStack` instead of collapsing to its content.
    public static let metaLineHeight: CGFloat = 22
}

// MARK: - Contrast

/// §2 non-negotiable rule 3: Increased Contrast lifts the collapsed opacities.
/// Components ask this type rather than hardcoding a percentage.
public struct ThirdHandContrast: Sendable {
    public let isIncreased: Bool

    public init(colorSchemeContrast: ColorSchemeContrast) {
        isIncreased = colorSchemeContrast == .increased
    }

    /// `TextSecondary` is asset-defined at 70% in the light/dark appearances;
    /// at increased contrast it must read as the full-strength variant.
    public var secondaryTextOpacity: Double { isIncreased ? 1.0 : 1.0 }
    /// Chip fills: 12% normally, 22% at increased contrast.
    public var chipFillOpacity: Double { isIncreased ? 0.22 : 0.12 }
    /// Separator: 30% normally, 55% at increased contrast.
    public var separatorOpacity: Double { isIncreased ? 0.55 : 1.0 }
}
