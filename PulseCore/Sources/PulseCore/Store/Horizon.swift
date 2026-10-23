import Foundation

/// The four board buckets, left to right. Raw values are the contract's display
/// names lowercased; the UI supplies localised titles.
public enum Horizon: String, Sendable, CaseIterable, Hashable {
    case now, next, later, niceToKnow

    /// The bucket order for `RawRepresentable`/`Codable` consumers.
    public var sortIndex: Int {
        switch self {
        case .now: 0
        case .next: 1
        case .later: 2
        case .niceToKnow: 3
        }
    }

    /// Whether "Now" should be tinted urgent. `niceToKnow` never is.
    public var isUrgent: Bool { self == .now }
}

extension Horizon: Codable {}

// MARK: - Derivation

/// Reads the board the way the Mac panel does.
///
/// Rules (from the plugin's panel and `docs/DATA-CONTRACT.md`):
///   * `fyi` is informational -> `.niceToKnow`, always, regardless of due date.
///   * `.now` when priority is `high`, or `due` is today or in the past.
///   * `.next` when `due` is within the next three days.
///   * otherwise `.later`.
///
/// Closed items have no horizon: `horizon(of:at:)` returns `nil` for
/// `done`/`dismissed`/`resolved`, and `horizonIgnoringClosed(...)` gives the
/// bucket the item *would* occupy, which is what the panel uses to place a
/// freshly closed row before it animates out. `isOnBoard` is the plain predicate.
///
/// "Today" and "within three days" are evaluated in `calendar`, which defaults to
/// the current one; tests pin it so the result does not depend on the machine.
public enum HorizonDerivation {
    /// How far ahead counts as `.next`.
    public static let nextWindowDays = 3

    /// The bucket an item belongs to, or `nil` when it is closed.
    public static func horizon(
        of item: PulseItem,
        at instant: Date,
        calendar: Calendar = .current
    ) -> Horizon? {
        let status = item.effectiveStatus(at: instant)
        guard !status.isClosed else { return nil }
        return bucket(for: item, at: instant, calendar: calendar)
    }

    /// The bucket regardless of closed state. Used for animation and for tests.
    public static func horizonIgnoringClosed(
        of item: PulseItem,
        at instant: Date,
        calendar: Calendar = .current
    ) -> Horizon {
        bucket(for: item, at: instant, calendar: calendar)
    }

    /// Whether the item should appear on the board at all.
    ///
    /// An item is on the board when it is not closed. `snoozed` counts as on the
    /// board: the contract deliberately keeps a snoozed item in the snapshot (and
    /// the panel shows it under Later until its snooze expires) instead of hiding
    /// it, so a user can see and unsnooze it.
    public static func isOnBoard(_ item: PulseItem, at instant: Date) -> Bool {
        !item.effectiveStatus(at: instant).isClosed
    }

    private static func bucket(for item: PulseItem, at instant: Date, calendar: Calendar) -> Horizon {
        if item.kind == .fyi { return .niceToKnow }
        if item.priority == .high { return .now }
        guard let due = item.due else { return .later }

        let dueDay = calendar.startOfDay(for: due)
        let today = calendar.startOfDay(for: instant)
        if dueDay <= today { return .now }

        let horizonEnd = calendar.date(byAdding: .day, value: nextWindowDays, to: today) ?? today
        if dueDay <= horizonEnd { return .next }
        return .later
    }
}

extension PulseItem {
    /// The item's board bucket right now, or `nil` when closed. See `HorizonDerivation`.
    public func horizon(at instant: Date, calendar: Calendar = .current) -> Horizon? {
        HorizonDerivation.horizon(of: self, at: instant, calendar: calendar)
    }
}

// MARK: - Sorting

/// The board's within-bucket order: priority ascending (high first), then `due`
/// ascending with undated items last, then `firstSeenAt` ascending. This is
/// `sortItems` in `lib/store.mjs` restated:
///
/// ```js
/// (PR[a.priority] - PR[b.priority]) ||
/// (d(a) < d(b) ? -1 : d(a) > d(b) ? 1 : 0) ||
/// (a.firstSeenAt < b.firstSeenAt ? -1 : 1)
/// ```
///
/// One deliberate difference: the JS comparator returns `1` when `firstSeenAt`
/// ties, which is an inconsistent comparator (Swift's `sort` would trap or
/// produce an arbitrary order). We break the remaining tie by `id`, which is
/// stable and keeps the sort total.
public enum PulseItemSort {
    public static func areInOrder(_ a: PulseItem, _ b: PulseItem) -> Bool {
        if a.priority.sortRank != b.priority.sortRank {
            return a.priority.sortRank < b.priority.sortRank
        }
        switch (a.due, b.due) {
        case let (ad?, bd?) where ad != bd:
            return ad < bd
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            break
        }
        if a.firstSeenAt != b.firstSeenAt { return a.firstSeenAt < b.firstSeenAt }
        return a.id < b.id
    }

    public static func sorted(_ items: [PulseItem]) -> [PulseItem] {
        items.sorted(by: areInOrder)
    }
}
