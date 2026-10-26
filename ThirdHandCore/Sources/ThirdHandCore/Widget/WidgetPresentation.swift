import Foundation

// MARK: - Reading the projection

//
// Everything the widgets and intents *derive* from `board.json` lives here, in
// `ThirdHandCore`, so it is visible to the app, the widget extension and the intent
// code without any of them importing the others. It is also plain Swift with an
// injected `now`, which is what makes it testable in `ThirdHandTests` without a
// widget host.

/// Board order for a projection.
///
/// `WidgetItem` carries only priority and due, not `firstSeenAt`, so the order is
/// restored from (priority, due) with the stored position as the stable tiebreak
/// -- exactly `ThirdHandItemSort` minus the field the projection deliberately drops.
public enum WidgetOrdering {
    public static func sorted(_ items: [WidgetItem]) -> [WidgetItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                let a = lhs.element
                let b = rhs.element
                let pa = Priority(rawValue: a.priority)?.sortRank ?? Priority.normal.sortRank
                let pb = Priority(rawValue: b.priority)?.sortRank ?? Priority.normal.sortRank
                if pa != pb {
                    return pa < pb
                }
                switch (a.due, b.due) {
                case let (ad?, bd?) where ad != bd: return ad < bd
                case (nil, .some): return false
                case (.some, nil): return true
                default: break
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

/// The board, projected for one widget render at one instant.
///
/// A value type with no I/O: `WidgetBoardReader` reads the file, this decides what
/// the widget shows, and the tests exercise this alone.
public struct WidgetSnapshot: Sendable, Hashable {
    /// How many Now items the user has. `.fyi` already excluded by the writer.
    public var nowCount: Int
    /// The Now items in board order. Empty is a legitimate state, not an error.
    public var nowItems: [WidgetItem]
    /// When the app last wrote the projection, or nil on a fresh install.
    public var generatedAt: Date?
    /// Whether `board.json` existed at all. Distinguishes "nothing needs you" from
    /// "the app has never run", which the widget must not lie about.
    public var hasBoard: Bool

    public init(
        nowCount: Int = 0,
        nowItems: [WidgetItem] = [],
        generatedAt: Date? = nil,
        hasBoard: Bool = false
    ) {
        self.nowCount = nowCount
        self.nowItems = nowItems
        self.generatedAt = generatedAt
        self.hasBoard = hasBoard
    }

    /// Projects a decoded board. `board == nil` is the missing-file state.
    public init(board: WidgetBoard?) {
        self.init()
        guard let board else { return }
        hasBoard = true
        generatedAt = board.generatedAt
        nowItems = WidgetOrdering.sorted(board.items.filter { $0.horizon == Horizon.now.rawValue })
        nowCount = board.nowCount
    }

    /// The top `limit` Now items for a Home Screen row list.
    public func topItems(limit: Int) -> [WidgetItem] {
        Array(nowItems.prefix(max(0, limit)))
    }

    /// How many Now items did not fit, for the "+N more" line.
    public func hiddenCount(limit: Int) -> Int {
        max(0, nowItems.count - max(0, limit))
    }

    public var isEmpty: Bool {
        nowItems.isEmpty
    }

    /// An empty board with a *known* board file vs a missing one. The widgets show the
    /// same sentence either way (#29 acceptance: "Nothing needs you" with a checkmark),
    /// but the distinction is kept on the type so a footer can offer setup instead.
    public var needsSetup: Bool {
        !hasBoard
    }

    /// The single most urgent item: the rectangular accessory, the Live Activity and
    /// Snooze Top all resolve it through here.
    public var topItem: WidgetItem? {
        nowItems.first
    }

    /// The highest priority present, for the circular gauge's tone.
    public var urgency: WidgetUrgency {
        guard !nowItems.isEmpty else { return .clear }
        let hasHigh = nowItems.contains { $0.priority == Priority.high.rawValue }
        if hasHigh {
            return .high
        }
        return nowCount >= WidgetCopy.urgencyThreshold ? .elevated : .normal
    }

    /// "3m" / "2h" / "4d" -- how old the projection is, for the small widget footer.
    public func ageText(now: Date) -> String {
        guard let generatedAt else { return "" }
        let seconds = max(0, now.timeIntervalSince(generatedAt))
        if seconds < 60 {
            return "now"
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        }
        if seconds < 86400 {
            return "\(Int(seconds / 3600))h"
        }
        return "\(Int(seconds / 86400))d"
    }
}

/// How loud the Now count should read. Names the tone rather than a colour, so the
/// views pick the token and `ThirdHandCore` stays UI-free (and monochrome-safe).
public enum WidgetUrgency: Sendable, Hashable {
    case clear, normal, elevated, high

    public var isUrgent: Bool {
        self == .elevated || self == .high
    }
}

// MARK: - Copy

/// Every string a widget or intent shows, as pure functions.
///
/// Kept out of the views so the truncation rules are asserted in tests rather than
/// discovered on a Lock Screen: `accessoryInline` in particular has a hard character
/// budget and must truncate at a word, never mid-word.
public enum WidgetCopy {
    /// The circular gauge caps at 9 (the design's 0-9 capacity) and reads "10+" past
    /// it, so a board with twelve Now items cannot overflow the numeral.
    public static let circularMax = 9
    /// The inline line truncates the title here plus an ellipsis (issue #30: 24).
    public static let inlineTitleLimit = 24
    /// How many Now items count as "a lot" for the elevated tone.
    public static let urgencyThreshold = 3
    /// The rectangular accessory shows the title over two lines; beyond this it is
    /// truncated so both lines stay readable.
    public static let rectangularTitleLimit = 60

    /// "10+" past the cap, else the numeral.
    public static func circularValue(_ count: Int) -> String {
        count > circularMax ? "\(circularMax)+" : "\(count)"
    }

    /// The gauge's fraction: full at the cap, so the ring is not permanently empty
    /// on a busy day.
    public static func circularFraction(_ count: Int) -> Double {
        guard count > 0 else { return 0 }
        return min(1, Double(count) / Double(circularMax))
    }

    /// "3 need you" / "1 needs you" / "Nothing needs you".
    public static func needYou(_ count: Int) -> String {
        switch count {
        case 0: emptyTitle
        case 1: "1 needs you"
        default: "\(count) need you"
        }
    }

    /// The VoiceOver label for a count, so it never reads a bare numeral.
    public static func countAccessibilityLabel(_ count: Int) -> String {
        switch count {
        case 0: emptyTitle
        case 1: "1 item needs you"
        default: "\(count) items need you"
        }
    }

    /// Truncates at a word boundary within `limit` characters, appending an ellipsis.
    /// A single unbroken word longer than the limit is hard-cut, because there is no
    /// better place to break it.
    public static func truncate(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let prefix = String(trimmed.prefix(limit))
        guard let lastSpace = prefix.lastIndex(of: " "),
              prefix.distance(from: prefix.startIndex, to: lastSpace) > limit / 3
        else {
            return prefix.trimmingCharacters(in: .whitespaces) + "\u{2026}"
        }
        return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// `accessoryInline`: one line, title truncated, no trailing punctuation.
    public static func inlineLine(_ snapshot: WidgetSnapshot) -> String {
        guard let top = snapshot.topItem else { return emptyTitle }
        return "\(snapshot.nowCount) need you \u{00B7} " + truncate(top.title, limit: inlineTitleLimit)
    }

    /// `accessoryRectangular` line 1: the most urgent item, truncated for two lines.
    public static func rectangularTitle(_ snapshot: WidgetSnapshot) -> String {
        guard let top = snapshot.topItem else { return emptyTitle }
        return truncate(top.title, limit: rectangularTitleLimit)
    }

    /// `accessoryRectangular` line 2: the due hint plus "+N more".
    ///
    /// "in 40m" for the next hour, "Today 5:30 PM" beyond it, and nothing when the
    /// item has no due date -- never an invented time.
    public static func rectangularDetail(
        _ snapshot: WidgetSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        var parts: [String] = []
        if snapshot.nowCount > 0 {
            parts.append(needYou(snapshot.nowCount))
        }
        if let due = snapshot.topItem?.due {
            parts.append(dueHint(due, now: now, calendar: calendar))
        }
        let more = snapshot.hiddenCount(limit: 1)
        if more > 0 {
            parts.append("+\(more) more")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The widget-sized due hint: relative inside the hour, otherwise the date chip.
    ///
    /// Deliberately re-derived rather than reusing `ThirdHandDateFormat.dueChip`, which
    /// lives in the app target and is not visible to the extension.
    public static func dueHint(_ due: Date, now: Date, calendar: Calendar = .current) -> String {
        let delta = due.timeIntervalSince(now)
        if delta < 0 {
            return "overdue"
        }
        if delta <= 3600 {
            return "in \(max(1, Int(delta / 60)))m"
        }
        if calendar.isDate(due, inSameDayAs: now) {
            return "Today " + time(due, calendar: calendar)
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: due)
        ).day ?? 0
        if days == 1 {
            return "Tomorrow"
        }
        if days > 1, days <= 6 {
            return weekday(due, calendar: calendar) + " " + time(due, calendar: calendar)
        }
        return monthDay(due, calendar: calendar)
    }

    /// Everything below formats in `calendar`'s time zone and locale rather than the
    /// device's: a due hint must agree with the calendar the count came from, or a test
    /// pinned to UTC would disagree with the widget's own render. A `Calendar` built
    /// without a locale (as tests do) would otherwise yield template placeholders from
    /// its symbol arrays, so a `DateFormatter` -- which falls back to `.current` --
    /// is used instead of indexing the symbols directly.
    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        formatter("EEE", calendar: calendar).string(from: date)
    }

    private static func monthDay(_ date: Date, calendar: Calendar) -> String {
        formatter("MMM d", calendar: calendar).string(from: date)
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter
    }

    private static func time(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// The medium widget's footer: "+2 more".
    public static func moreLine(_ count: Int) -> String? {
        count > 0 ? "+\(count) more" : nil
    }

    /// The empty-state title, shared by the small widget and the accessory families
    /// so they cannot disagree.
    public static let emptyTitle = "Nothing needs you"
    public static let emptyGlyph = "checkmark.circle"
}

// MARK: - Live Activity decision

/// Whether an `Activity` should start, purely decided.
///
/// The app-side controller owns the ActivityKit calls; this owns the rule, so the
/// "within 60 minutes" boundary and the no-duplicate rule are testable.
public enum ImminentItemRule {
    /// Issue #31 / `Classifier.imminentWindow`: a start exactly 60 minutes away
    /// counts, so the comparison is inclusive.
    public static let imminentWindow: TimeInterval = 60 * 60

    /// The item the Live Activity should describe: the nearest-due `Now` item that
    /// starts inside the window and has not already started.
    ///
    /// All-day events never arrive here as imminent (the classifier refuses to make
    /// an imminent row out of one, so the item is either absent or carries no
    /// meaningful `due`); what this adds is the "already started" exclusion, since a
    /// countdown to a past instant is nonsense.
    public static func imminentItem(_ snapshot: WidgetSnapshot, now: Date) -> WidgetItem? {
        let candidates = snapshot.nowItems.compactMap { item -> (WidgetItem, Date)? in
            guard let due = item.due else { return nil }
            let delta = due.timeIntervalSince(now)
            guard delta >= 0, delta <= imminentWindow else { return nil }
            return (item, due)
        }
        return candidates.min { $0.1 < $1.1 }?.0
    }

    /// Whether to start a new activity, given what is already running.
    ///
    /// Returns nil when nothing is imminent, and nil when the running activity
    /// already describes this item -- a second capture pass must not duplicate it.
    public static func shouldStart(
        snapshot: WidgetSnapshot,
        now: Date,
        runningItemID: String?
    ) -> WidgetItem? {
        guard let item = imminentItem(snapshot, now: now), item.id != runningItemID else { return nil }
        return item
    }

    /// Whether a running activity is over: its item left the board entirely (done,
    /// snoozed, or dropped by a capture pass).
    public static func shouldEnd(runningItemID: String, snapshot: WidgetSnapshot) -> Bool {
        !snapshot.nowItems.contains { $0.id == runningItemID }
    }

    /// "in 40 min" / "starting now" for the countdown.
    public static func countdownText(_ start: Date, now: Date) -> String {
        let delta = start.timeIntervalSince(now)
        if delta <= 0 {
            return "starting now"
        }
        let minutes = max(1, Int((delta / 60).rounded(.up)))
        return "in \(minutes) min"
    }
}

// MARK: - Intent summary

/// The spoken summary "What needs me" returns, as a pure function.
///
/// Kept here so the phrasing for an empty, one-item and many-item board is asserted
/// in tests rather than tuned by ear on a device.
public enum IntentSummary {
    /// How many items the spoken line names before it says "and N more".
    public static let spokenItemLimit = 2

    /// "3 things need you: Design review, in 40m, RSVP to Priya."
    ///
    /// Empty reads "Nothing needs you." with no trailing colon, which is what Siri
    /// reads back cleanly.
    public static func whatNeedsMe(_ snapshot: WidgetSnapshot, now: Date, calendar: Calendar = .current) -> String {
        let count = snapshot.nowCount
        guard count > 0 else { return WidgetCopy.emptyTitle + "." }

        let headline = count == 1 ? "1 thing needs you" : "\(count) things need you"

        let named = snapshot.topItems(limit: spokenItemLimit).map { item -> String in
            guard let due = item.due else { return item.title }
            return "\(item.title), \(WidgetCopy.dueHint(due, now: now, calendar: calendar))"
        }
        guard !named.isEmpty else { return headline + "." }

        let remaining = count - named.count
        let tail = remaining > 0 ? " and \(remaining) more" : ""
        return headline + ": " + named.joined(separator: ", ") + tail + "."
    }

    /// "Snoozed Design review until 9:00 AM."
    public static func snoozed(title: String, until: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = calendar.timeZone
        return "Snoozed \(title) until \(until.formatted(style))."
    }

    /// The empty-board refusal for Snooze Top: names what did not happen.
    public static let nothingToSnooze = "Nothing needs you, so there was nothing to snooze."
}
