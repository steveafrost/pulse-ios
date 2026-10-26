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
    /// The row's leading rail when the row is *not* urgent.
    ///
    /// Added in the craft pass. The rail used to be painted in the horizon tint,
    /// so every Now row got a saturated red spine and the board read as a wall of
    /// alarms — which contradicts §1's own "urgency is position, not colour". A
    /// neutral rail keeps the structural cue (this card has a horizon) while the
    /// *only* red on the board is the one row that is genuinely urgent.
    public static let railNeutral = Color("RailNeutral")

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
    ///
    /// Tightened in the craft pass. 72/92/112 were sized for a card that had to
    /// hold a title, a detail *and* a two-chip meta strip while carrying 14pt of
    /// vertical padding; measured against the shipped board, only three rows fit
    /// above the FAB, which is the opposite of a board you scan in two seconds.
    /// These are now the floor the content naturally needs at the default size and
    /// growth past them stays entirely text-driven — nothing here caps a row.
    public static let rowTitleMinHeight: CGFloat = 56
    public static let rowTitleDetailMinHeight: CGFloat = 76
    public static let rowFullMinHeight: CGFloat = 92
}

public enum ThirdHandRadius {
    public static let card: CGFloat = 16
    public static let widget: CGFloat = 20
    public static let sheetTop: CGFloat = 28
    public static let chip: CGFloat = 4
    public static let capsule: CGFloat = 999
    /// Unused since the row rail was removed; kept until the next asset sweep so
    /// this edit does not touch the design-token surface for unrelated views.
    public static let rail: CGFloat = 1.5
}

// MARK: - Typography
//
// §3: `.system` text styles only — no fixed point sizes anywhere, because a fixed
// size breaks Dynamic Type. Weight is the only axis besides style.

public enum ThirdHandTypography {
    /// The display face: **New York**, reached through `design: .serif`.
    ///
    /// This is the craft pass's one deliberate voice. It ships with the system, so
    /// there is no font file to bundle, license or verify, and because it is a
    /// *text style* rather than a point size it scales through Dynamic Type and
    /// reflows at AX5 exactly as SF does. A high-contrast serif on the two things
    /// that name the board — its title and its horizon headings — reads as a
    /// considered ledger. The numbers, dates, chips and labels around it stay SF
    /// Pro so scanning stays as fast as the task demands. Distinctiveness lives in
    /// the two headings and nowhere else: a serif row title would slow the scan,
    /// and a serif footnote would be muddy at meta size.
    public static let boardTitle = Font.system(.largeTitle, design: .serif, weight: .bold)
    public static let sectionHeader = Font.system(.title3, design: .serif, weight: .semibold)

    public static let sectionHint = Font.system(.footnote, weight: .regular)
    public static let itemTitle = Font.system(.headline, weight: .semibold)
    public static let itemDetail = Font.system(.subheadline, weight: .regular)
    public static let meta = Font.system(.footnote, weight: .regular)
    public static let chip = Font.system(.caption2, weight: .medium)
    public static let badgeCount = Font.system(.caption, design: .rounded, weight: .bold)
    public static let buttonLabel = Font.system(.body, weight: .semibold)
    public static let captureCapsule = Font.system(.footnote, weight: .medium)
    public static let emptyTitle = Font.system(.title2, design: .serif, weight: .semibold)
    public static let emptyBody = Font.system(.body, weight: .regular)
    public static let eyebrow = Font.system(.caption2, weight: .semibold)
    public static let keyValueLabel = Font.system(.subheadline, weight: .semibold)
}

// MARK: - Tracking
//
// Letterspacing is the cheap way to buy distinctiveness without a bundled face.
// It is applied only where it cannot hurt legibility: a small-cap eyebrow over a
// group, and the horizon count, which is a numeral rather than prose. Everything
// read as a sentence keeps default tracking.
public enum ThirdHandTracking {
    /// Section eyebrows and group labels — the "SOURCES" above a settings list.
    public static let eyebrow: CGFloat = 0.8
    /// The horizon count after a heading. Opens it up just enough that a two-digit
    /// count does not read as part of the word before it.
    public static let count: CGFloat = 0.5
}

// MARK: - Hairlines

public enum ThirdHandMetrics {
    /// `railWidth` / `railWidthUrgent` were removed with the row rail. Cards no
    /// longer carry a leading spine, so there is no width to tune.
    public static let hairline: CGFloat = 1
    public static let kindGlyphSize: CGFloat = 20
    public static let newnessDot: CGFloat = 6
    public static let emptyGlyphSize: CGFloat = 64
    /// The board row's meta strip height, so the horizontal scroller has a
    /// definite height inside a `VStack` instead of collapsing to its content.
    public static let metaLineHeight: CGFloat = 22

    // MARK: Signature moment (§7.5)
    /// Each row starts this long after the one above it.
    public static let loadInStagger: Double = 0.032
    /// How far a row rises as it settles. Small on purpose: this is a breath, not
    /// a bounce, and anything larger reads as decoration on a board checked 100
    /// times a day.
    public static let loadInRise: CGFloat = 10
    /// Rows past this index all share one delay, so a 40-row board does not take
    /// one and a half seconds to finish arriving.
    public static let loadInStaggerCap: Double = 0.24
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
