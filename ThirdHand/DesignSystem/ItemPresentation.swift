import Foundation
import SwiftUI
import ThirdHandCore

// MARK: - Horizon

/// §2 / §4.1: `Horizon` owns the glyph, tint and collapse limit for each bucket;
/// every other table derives from it. Keeping that in one extension means the
/// board, the detail sheet and the history timeline cannot disagree.
public extension Horizon {
    var title: String {
        switch self {
        case .now: "Now"
        case .next: "Next"
        case .later: "Later"
        case .niceToKnow: "Nice to Know"
        }
    }

    /// §4.1 hints. They hide at AX1+ (§3) but the board also uses them for
    /// VoiceOver on the section header, so they still exist.
    var hint: String {
        switch self {
        case .now: "High priority or due today"
        case .next: "Due in the next three days"
        case .later: "Further out"
        case .niceToKnow: "Good to know"
        }
    }

    var systemImage: String {
        switch self {
        case .now: "exclamationmark.circle.fill"
        case .next: "arrow.right.circle.fill"
        case .later: "clock.fill"
        case .niceToKnow: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .now: ThirdHandColor.horizonNow
        case .next: ThirdHandColor.horizonNext
        case .later: ThirdHandColor.horizonLater
        case .niceToKnow: ThirdHandColor.horizonFYI
        }
    }

    /// §4.1: before "Show all" appears a section shows `.now` 3, `.next` 4,
    /// `.later` 3, `.fyi` 2.
    var collapseLimit: Int {
        switch self {
        case .now: 3
        case .next: 4
        case .later: 3
        case .niceToKnow: 2
        }
    }

    /// §5.1 rule 1: Nice to Know has no leading rail.
    var hasRail: Bool {
        self != .niceToKnow
    }
}

// MARK: - Kind

public extension Kind {
    var systemImage: String {
        switch self {
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

    var title: String {
        switch self {
        case .reply: "Reply"
        case .decision: "Decision"
        case .rsvp: "RSVP"
        case .conflict: "Conflict"
        case .deadline: "Deadline"
        case .review: "Review"
        case .followup: "Follow-up"
        case .fyi: "FYI"
        }
    }

    /// §5.3 spoken labels, used in the row's composed VoiceOver label.
    var spokenLabel: String {
        switch self {
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

    var tint: Color {
        switch self {
        case .deadline: ThirdHandColor.kindDeadline
        case .decision, .rsvp, .conflict: ThirdHandColor.kindAttention
        case .reply, .review, .followup, .fyi: ThirdHandColor.kindNeutral
        }
    }
}

// MARK: - Source

public extension Source {
    var systemImage: String {
        switch self {
        case .calendar: "calendar"
        case .gmail: "envelope"
        case .slack: "number.square"
        case .github, .docs, .other: "link"
        }
    }

    var title: String {
        switch self {
        case .calendar: "Calendar"
        case .gmail: "Email"
        case .slack: "Slack"
        case .github: "GitHub"
        case .docs: "Docs"
        case .other: "Link"
        }
    }

    /// §5.3 spoken labels.
    var spokenLabel: String {
        switch self {
        case .calendar: "from Calendar"
        case .gmail: "from Email"
        case .slack: "from Slack"
        case .github: "from a link"
        case .docs: "from Docs"
        case .other: "from a link"
        }
    }

    var tint: Color {
        switch self {
        case .calendar: ThirdHandColor.sourceCalendar
        case .gmail: ThirdHandColor.sourceGmail
        case .slack: ThirdHandColor.sourceSlack
        case .other, .github, .docs: ThirdHandColor.sourceOther
        }
    }
}

// MARK: - Priority

public extension Priority {
    var title: String {
        switch self {
        case .high: "High"
        case .normal: "Normal"
        case .low: "Low"
        }
    }

    var spokenLabel: String {
        switch self {
        case .high: "high priority"
        case .normal: "normal priority"
        case .low: "low priority"
        }
    }

    var tint: Color {
        switch self {
        case .high: ThirdHandColor.horizonNow
        case .normal: ThirdHandColor.textSecondary
        case .low: ThirdHandColor.textTertiary
        }
    }
}

// MARK: - Status

public extension Status {
    var title: String {
        switch self {
        case .open: "Open"
        case .waiting: "Waiting"
        case .snoozed: "Snoozed"
        case .resolved: "Resolved"
        case .done: "Done"
        case .dismissed: "Dismissed"
        }
    }

    var tint: Color {
        switch self {
        case .waiting: ThirdHandColor.statusWaiting
        case .snoozed: ThirdHandColor.statusSnoozed
        case .done, .resolved: ThirdHandColor.statusDone
        case .dismissed: ThirdHandColor.textTertiary
        case .open: ThirdHandColor.textSecondary
        }
    }
}

// MARK: - Due formatting

/// The board's due chip and the detail's `KeyValue` row both come from here so
/// "Today 5:30 PM" never becomes "Today 17:30" in one place and not the other.
public enum ThirdHandDateFormat {
    /// §5.1: the meta line uses `Date.FormatStyle`, "Today 5:30 PM".
    /// §5.1: the due chip. Whatever the row can spare is in the time: it is
    /// omitted at exactly midnight, and everything within a week is relative
    /// ("Today 5:30 PM", "Tomorrow", "Monday"). The row truncates rather than
    /// wrapping, so the shortest honest form wins.
    public static func dueChip(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = clock(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) {
            return time.map { "Today \($0)" } ?? "Today"
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        if let tomorrow, calendar.isDate(date, inSameDayAs: tomorrow) {
            return time.map { "Tomorrow \($0)" } ?? "Tomorrow"
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        if days > 1, days <= 6 {
            let weekday = date.formatted(.dateTime.weekday(.wide))
            return time.map { "\(weekday) \($0)" } ?? weekday
        }
        // A week or more out, the clock time is the least useful part of the
        // chip and the row cannot hold "Oct 21 5:00 AM" beside the age, so only
        // the date survives; the exact time is on the detail sheet.
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// The time, or `nil` when the date is exactly midnight (a date-only due date).
    private static func clock(_ date: Date, calendar: Calendar) -> String? {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        guard parts.hour != 0 || parts.minute != 0 else { return nil }
        return date.formatted(.dateTime.hour().minute())
    }

    /// §5.3: "Due today at 5:30 PM" / "Due Monday at 3 PM" / "No due date".
    public static func duePhrase(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let date else { return "No due date" }
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) {
            return "Due today at \(time)"
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        if days == 1 {
            return "Due tomorrow at \(time)"
        }
        if days < 0 {
            return "Overdue, was due \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        }
        if days <= 6 {
            return "Due \(date.formatted(.dateTime.weekday(.wide))) at \(time)"
        }
        return "Due \(date.formatted(.dateTime.month(.wide).day())) at \(time)"
    }

    /// §5.1: "5h ago".
    public static func relative(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60))m ago"
        }
        if seconds < 86400 {
            return "\(Int(seconds / 3600))h ago"
        }
        return "\(Int(seconds / 86400))d ago"
    }

    /// §5.3: "Seen 5 hours ago".
    public static func relativePhrase(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return "seen just now"
        }
        if seconds < 3600 {
            return "seen \(Int(seconds / 60)) minutes ago"
        }
        if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "seen \(hours) hour\(hours == 1 ? "" : "s") ago"
        }
        let days = Int(seconds / 86400)
        return "seen \(days) day\(days == 1 ? "" : "s") ago"
    }

    /// "until 9:00 AM" for a snoozed row.
    public static func snoozeUntil(_ date: Date) -> String {
        "until " + date.formatted(.dateTime.hour().minute())
    }
}

// MARK: - People

public enum ThirdHandPeople {
    /// §5.1: first names, max two, then "+N".
    public static func shortLine(_ people: [String], limit: Int = 2) -> String {
        guard !people.isEmpty else { return "" }
        let firstNames = people.prefix(limit).map { $0.split(separator: " ").first.map(String.init) ?? $0 }
        let joined = firstNames.joined(separator: ", ")
        let extra = people.count - min(people.count, limit)
        return extra > 0 ? "\(joined) +\(extra)" : joined
    }

    /// §5.3: "With Priya and Marco" / "With Priya and 1 other".
    public static func spokenPhrase(_ people: [String], limit: Int = 2) -> String {
        guard let first = people.first else { return "" }
        let firstName = first.split(separator: " ").first.map(String.init) ?? first
        guard people.count > 1 else { return "With \(firstName)" }
        if people.count == 2 {
            let second = people[1].split(separator: " ").first.map(String.init) ?? people[1]
            return "With \(firstName) and \(second)"
        }
        let others = people.count - 1
        return "With \(firstName) and \(others) other\(others == 1 ? "" : "s")"
    }
}

// MARK: - Source identity

/// The board's source chip. The wire `Source` enum has no `reminders` case (the
/// contract stores reminders items with a `reminders:` id prefix, which the store
/// maps to `.other`), so the UI derives its own identity from the id prefix. That
/// keeps "Reminders" visible on the board without touching `ThirdHandCore`.
public enum SourceIdentity: String, Sendable, CaseIterable, Hashable, Identifiable {
    case calendar, reminders, email, slack, docs, other

    public var id: String {
        rawValue
    }

    public init(item: ThirdHandItem) {
        let prefix = item.id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        switch prefix {
        case "calendar": self = .calendar
        case "reminders": self = .reminders
        case "gmail": self = .email
        case "slack": self = .slack
        case "docs": self = .docs
        default:
            switch item.source {
            case .calendar: self = .calendar
            case .gmail: self = .email
            case .slack: self = .slack
            case .docs: self = .docs
            default: self = .other
            }
        }
    }

    public var title: String {
        switch self {
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .email: "Email"
        case .slack: "Slack"
        case .docs: "Docs"
        case .other: "Link"
        }
    }

    public var systemImage: String {
        switch self {
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .email: "envelope"
        case .slack: "number.square"
        case .docs: "doc.text"
        case .other: "link"
        }
    }

    /// §5.3 spoken labels.
    public var spokenLabel: String {
        switch self {
        case .calendar: "from Calendar"
        case .reminders: "from Reminders"
        case .email: "from Email"
        case .slack: "from Slack"
        case .docs: "from Docs"
        case .other: "from a link"
        }
    }

    public var tint: Color {
        switch self {
        case .calendar: ThirdHandColor.sourceCalendar
        case .reminders: ThirdHandColor.sourceReminders
        case .email: ThirdHandColor.sourceGmail
        case .slack: ThirdHandColor.sourceSlack
        case .docs, .other: ThirdHandColor.sourceOther
        }
    }

    /// §8.1 filter-bar order: Calendar / Reminders / Email / Slack / Docs.
    public static let filterOrder: [SourceIdentity] = [.calendar, .reminders, .email, .slack, .docs, .other]
}

// MARK: - Item additions

public extension ThirdHandItem {
    var sourceIdentity: SourceIdentity {
        SourceIdentity(item: self)
    }

    var isSnoozed: Bool {
        status == .snoozed
    }

    /// §5.1 rule 1, revised in the craft pass: the rail is a *quiet spine* unless
    /// the row is genuinely urgent.
    ///
    /// It previously took `horizon.tint`, so every Now row carried a saturated red
    /// stripe and the board read as a wall of alarms. §1 says "urgency is position,
    /// not colour"; the rail was contradicting it. Now:
    ///
    /// - urgent (high priority **and** due within 24h, including overdue) →
    ///   `HorizonNow`, and the rail also thickens (`isUrgent`).
    /// - high priority further out → `HorizonNext`.
    /// - everything else → `RailNeutral`, a structural cue that this card has a
    ///   horizon without asserting an alarm.
    ///
    /// The horizon is still unmistakable from the section it sits under and from
    /// the header glyph, so no information is lost — only emphasis.
    ///
    /// Note on the demo fixture: every Now row in it is high-priority and overdue,
    /// so all three rails are legitimately red there and the rationing is invisible
    /// in that screenshot. It shows up on the ordinary case — a Now row that is
    /// merely due today and not high priority now gets a quiet rail where it used to
    /// get a red one.
    func railTint(horizon: Horizon, now: Date) -> Color {
        guard horizon.hasRail else { return .clear }
        if isUrgent(now: now) {
            return ThirdHandColor.horizonNow
        }
        if priority == .high {
            return ThirdHandColor.horizonNext
        }
        return ThirdHandColor.railNeutral
    }

    /// High priority *and* due inside a day — the only state that earns the Now
    /// rail colour and the thicker rail.
    ///
    /// No lower bound on purpose. An overdue high-priority item is *more* urgent
    /// than one due in an hour, so it must keep the red spine; clamping the past
    /// away (as a first draft of this did) silently demoted exactly the rows that
    /// most needed the emphasis.
    func isUrgent(now: Date) -> Bool {
        guard priority == .high, let due else { return false }
        return due.timeIntervalSince(now) <= 86400
    }

    /// §5.2: newness derives from the snapshot's `lastViewedAt`.
    func isNew(since lastViewedAt: Date?) -> Bool {
        guard let lastViewedAt else { return true }
        return firstSeenAt > lastViewedAt
    }
}

// MARK: - Colour import
