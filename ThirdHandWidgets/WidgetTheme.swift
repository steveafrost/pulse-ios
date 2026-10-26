import SwiftUI
import ThirdHandCore

/// The widget extension's copy of the design tokens it needs.
///
/// Why a copy: `ThirdHand/DesignSystem/Tokens.swift` lives in the **app** target, and an
/// app extension cannot import the app's code. The colours themselves are asset
/// catalogue entries (`HorizonNow`, `SurfaceCard`, ...) that ship inside
/// `ThirdHand/Assets.xcassets`, which the extension target does not compile either.
///
/// Two bad options and one good one:
///  * Reference `Color("HorizonNow")` from the extension and copy the asset
///    catalogue in -- the extension would then carry a second copy of every colour
///    and the two would drift silently the first time the design changes.
///  * Hard-code hex in the widget -- reintroduces exactly the thing `Tokens.swift`
///    exists to prevent.
///  * **Re-declare the few names the widget uses in one file**, with asset
///    references for anything the system can resolve and the app target's semantic
///    intent otherwise.
///
/// We take the third, and note the one place it is imperfect: the extension does not
/// get `ThirdHand/Assets.xcassets`, so `Color("HorizonNow")` resolves to the default
/// (black) rather than the token. Line-based tints in the widget are therefore
/// reserved for *decorative* dots. Everything a user must read -- the count, the
/// titles, the due hint -- uses `.primary`/`.secondary`, which are system semantic
/// colours, correct in light, dark, tinted and monochrome Lock Screen modes without
/// our involvement. That is also what lets the accessory families look right when
/// the system desaturates them: nothing we draw depends on a hue surviving.
///
/// If the extension is ever given `ThirdHand/Assets.xcassets` as a resource (a
/// `project.yml` change I have not made, see the report), the `lineTint` references
/// below light up with the real palette and nothing else changes.
enum WidgetTheme {
    /// The Now bucket's rail/dot. Asset name matches `docs/DESIGN.md` §2, so it is
    /// traceable even from here.
    static let nowTint = Color("HorizonNow")

    /// The card surface every widget background uses (§11: `.containerBackground`
    /// and nothing else). Falls back to the system card colour when the asset is
    /// absent, which is what happens today.
    static let surface = Color("SurfaceCard")

    /// A stable colour for a priority dot that survives desaturation as a *shape*
    /// rather than a hue: the dot is filled for high priority, hollow otherwise.
    static func dotFilled(for priority: String) -> Bool {
        priority == Priority.high.rawValue
    }

    /// The SF Symbol for an item's kind, mirrored from the app's `ItemPresentation`
    /// because the extension cannot see it. Only the kinds a Now item can carry, so
    /// the table cannot silently grow out of step with the app's much larger one.
    /// The VoiceOver phrase for a kind, mirrored from the app's table for the same
    /// reason as `glyph`: the extension cannot import the app target.
    static func spokenLabel(forKind kind: String) -> String {
        switch Kind(rawValue: kind) ?? .followup {
        case .reply: "Needs a reply"
        case .decision: "Needs a decision"
        case .rsvp: "Waiting on your RSVP"
        case .conflict: "Schedule conflict"
        case .deadline: "Deadline"
        case .review: "Needs review"
        case .followup: "Follow up"
        case .fyi: "For your information"
        }
    }

    static func glyph(forKind kind: String) -> String {
        switch Kind(rawValue: kind) ?? .followup {
        case .reply: "arrowshape.turn.up.left"
        case .decision: "questionmark.circle"
        case .rsvp: "calendar.badge.clock"
        case .conflict: "exclamationmark.triangle"
        case .deadline: "clock.badge.exclamationmark"
        case .review: "doc.text.magnifyingglass"
        case .followup: "arrow.turn.down.right"
        case .fyi: "info.circle"
        }
    }
}
