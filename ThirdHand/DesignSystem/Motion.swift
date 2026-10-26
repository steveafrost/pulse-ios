import SwiftUI

/// §7. Three animations ship and no others. Everything here is a *decision*, not
/// a duration copied into a view, and every one of them has a Reduce Motion
/// answer: the reduced variants are properties on the same type so a call site
/// cannot forget to check.
public struct ThirdHandMotion: Sendable {
    public let reduceMotion: Bool

    public init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    public init(accessibilityReduceMotion: Bool) {
        self.init(reduceMotion: accessibilityReduceMotion)
    }

    // MARK: Row -> detail (§7.1)

    /// The namespace morph. Reduced motion presents the sheet plainly instead.
    public var rowToDetail: Animation {
        .snappy(duration: 0.38, extraBounce: 0.02)
    }

    public var detailDismiss: Animation {
        .snappy(duration: 0.3)
    }

    /// The row's content fades 1 -> 0.35 over 0.18s as the sheet covers it.
    public var rowUnderSheet: Animation {
        .easeOut(duration: 0.18)
    }

    public var rowUnderSheetOpacity: Double {
        0.35
    }

    // MARK: Completion (§7.2)

    /// Step 2: the card flashes `StatusDone` and back.
    public static let completionFlashDuration: Double = 0.32
    /// Step 3: the card collapses.
    public static let completionCollapseDuration: Double = 0.24
    /// Steps 2/3 begin here.
    public static let completionFlashDelay: Double = 0.12

    public var completionFlash: Animation {
        .easeOut(duration: Self.completionFlashDuration)
    }

    public var completionCollapse: Animation {
        .smooth(duration: Self.completionCollapseDuration)
    }

    /// Step 4: the list closes the gap as one unit. Reduced motion jumps.
    public var listGap: Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(
            response: 0.42,
            dampingFraction: 0.86
        )
    }

    /// Step 5: a fully empty board cross-fades to "All clear".
    public var emptyBoard: Animation {
        .easeInOut(duration: reduceMotion ? 0.2 : 0.3)
    }

    // MARK: Section reorder (§7.3)

    public var sectionDeparture: Animation {
        .smooth(duration: 0.28)
    }

    public var sectionArrival: Animation {
        .smooth(duration: reduceMotion ? 0.01 : 0.28)
    }

    public var sectionArrivalDelay: Double {
        reduceMotion ? 0 : 0.06
    }

    /// "Show 4 more" expansion (§4.1).
    public var sectionExpansion: Animation {
        .smooth(duration: reduceMotion ? 0.01 : 0.25)
    }

    // MARK: Reductions

    /// §7.4: `.symbolEffect(.bounce)` is dropped entirely.
    public var allowsSymbolEffect: Bool {
        !reduceMotion
    }

    /// §7.1: matched geometry is swapped for a standard sheet + cross-fade.
    public var allowsMatchedGeometry: Bool {
        !reduceMotion
    }

    /// §7.2 step 3: instant removal rather than a collapse.
    public var removalTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity,
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }
}

// MARK: - Environment plumbing

public extension EnvironmentValues {
    @Entry var pulseMotion: ThirdHandMotion = .init(reduceMotion: false)
}

/// Injects a `ThirdHandMotion` honouring the system Reduce Motion setting. Applied
/// once, at the board root, so every descendant reads the same value.
public struct ThirdHandMotionScope: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content.environment(\.pulseMotion, ThirdHandMotion(reduceMotion: reduceMotion))
    }
}

public extension View {
    func pulseMotionScope() -> some View {
        modifier(ThirdHandMotionScope())
    }
}
