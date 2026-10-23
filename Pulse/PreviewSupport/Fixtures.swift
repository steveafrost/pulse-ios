#if DEBUG
import Foundation
import PulseCore

/// Deterministic fixtures (#23). Every timestamp derives from `fixtureNow`, so a
/// preview, a screenshot and an accessibility audit all see the same board.
/// Nothing here is referenced from production code — `FixtureSet` is preview- and
/// test-only by convention, and the previews are the only call sites.
public enum Fixtures {
    /// The single instant every fixture derives from: 2026-10-23 09:00 UTC.
    public static let fixtureNow: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 23
        components.hour = 9
        components.minute = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 1_793_059_200)
    }()

    public static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    public static func ago(_ seconds: TimeInterval) -> Date { fixtureNow.addingTimeInterval(-seconds) }
    public static func after(_ seconds: TimeInterval) -> Date { fixtureNow.addingTimeInterval(seconds) }

    public static func hour(_ h: Double) -> TimeInterval { h * 3_600 }
    public static func day(_ d: Double) -> TimeInterval { d * 86_400 }

    // MARK: Base builder

    public static func item(
        id: String,
        source: Source = .calendar,
        kind: Kind = .reply,
        title: String,
        detail: String = "",
        url: String? = nil,
        due: Date? = nil,
        priority: Priority = .normal,
        people: [String] = [],
        status: Status = .open,
        snoozedUntil: Date? = nil,
        resolution: String? = nil,
        firstSeenAt: Date? = nil,
        lastSeenAt: Date? = nil,
        quickActions: [QuickAction] = [],
        history: [HistoryEntry]? = nil
    ) -> PulseItem {
        let firstSeen = firstSeenAt ?? ago(hour(5))
        let lastSeen = lastSeenAt ?? firstSeen
        return PulseItem(
            id: id,
            source: source,
            kind: kind,
            title: title,
            detail: detail,
            url: url,
            due: due,
            priority: priority,
            people: people,
            status: status,
            snoozedUntil: snoozedUntil,
            resolution: resolution,
            firstSeenAt: firstSeen,
            lastSeenAt: lastSeen,
            updatedAt: lastSeen,
            resolvedAt: status.isClosed ? lastSeen : nil,
            lastChangedBy: "capture",
            history: history ?? [
                HistoryEntry(at: firstSeen, by: "capture", change: "created")
            ],
            quickActions: quickActions
        )
    }

    // MARK: Named fixtures

    public static var highPriorityRSVP: PulseItem {
        item(
            id: "calendar:event:rsvp-design-review",
            kind: .rsvp,
            title: "RSVP to the design review",
            detail: "Priya needs a yes before she books the room for the redesign kickoff.",
            due: after(hour(0.66)),
            priority: .high,
            people: ["Priya Nair", "Marco Alves", "Dana Whitfield", "Sam Okoro"],
            firstSeenAt: ago(day(1)),
            lastSeenAt: ago(hour(2)),
            quickActions: [
                QuickAction(label: "Yes, I'll be there", text: "Yes — I'll be at the design review."),
                QuickAction(label: "Open invite", url: "https://calendar.example.com/rsvp/design-review"),
            ]
        )
    }

    public static var imminentMeeting: PulseItem {
        item(
            id: "calendar:event:standup",
            kind: .deadline,
            title: "Weekly standup",
            detail: "Agenda is in the thread; bring the milestone update.",
            due: after(hour(0.4)),
            priority: .high,
            people: ["Priya Nair"],
            firstSeenAt: ago(day(3)),
            lastSeenAt: ago(hour(1))
        )
    }

    public static var overdueReminder: PulseItem {
        item(
            id: "reminders:reminder:file-invoices",
            kind: .deadline,
            title: "File the October invoices",
            detail: "Two are still waiting on the vendor reference number.",
            due: ago(day(2)),
            priority: .high,
            firstSeenAt: ago(day(4)),
            lastSeenAt: ago(day(1))
        )
    }

    public static var conflict: PulseItem {
        item(
            id: "calendar:conflict:20261023:8f3a1c2b",
            kind: .conflict,
            title: "Design review overlaps the vendor call",
            detail: "Both are accepted and they overlap by 20 minutes this afternoon.",
            due: after(hour(6)),
            priority: .high,
            people: ["Priya Nair", "Marco Alves"],
            firstSeenAt: ago(hour(3)),
            lastSeenAt: ago(hour(3))
        )
    }

    public static var fyiLink: PulseItem {
        item(
            id: "docs:page:quarterly-notes",
            source: .docs,
            kind: .fyi,
            title: "Quarterly planning notes are up",
            detail: "Shared just now, no action needed.",
            url: "https://docs.example.com/quarterly-notes",
            priority: .low,
            firstSeenAt: ago(hour(1)),
            lastSeenAt: ago(hour(1))
        )
    }

    public static var snoozedUntilTomorrow: PulseItem {
        item(
            id: "gmail:message:vendor-quote",
            source: .gmail,
            kind: .reply,
            title: "Reply to the vendor quote",
            detail: "The new quote came in under budget — answer when you have the numbers.",
            priority: .normal,
            status: .snoozed,
            snoozedUntil: after(day(1)),
            firstSeenAt: ago(day(2)),
            lastSeenAt: ago(day(2)),
            history: [
                HistoryEntry(at: ago(day(2)), by: "capture", change: "created"),
                HistoryEntry(at: ago(hour(4)), by: "user", change: "snoozed", until: after(day(1))),
            ]
        )
    }

    public static var doneWithReason: PulseItem {
        item(
            id: "calendar:event:contract-review",
            kind: .review,
            title: "Review the vendor contract",
            detail: "Legal sent the redlines.",
            priority: .normal,
            status: .done,
            resolution: "Signed and returned this morning.",
            firstSeenAt: ago(day(2)),
            lastSeenAt: ago(hour(2)),
            history: [
                HistoryEntry(at: ago(day(2)), by: "capture", change: "created"),
                HistoryEntry(at: ago(hour(2)), by: "user", change: "done", reason: "Signed and returned this morning."),
            ]
        )
    }

    public static func dismissed() -> PulseItem {
        item(
            id: "gmail:message:newsletter",
            source: .gmail,
            kind: .fyi,
            title: "Weekly product newsletter",
            priority: .low,
            status: .dismissed,
            firstSeenAt: ago(day(1)),
            lastSeenAt: ago(day(1))
        )
    }

    public static func resolved() -> PulseItem {
        item(
            id: "calendar:event:office-hours",
            kind: .followup,
            title: "Office hours with Marco",
            status: .resolved,
            firstSeenAt: ago(day(3)),
            lastSeenAt: ago(day(1))
        )
    }

    public static var withThreeQuickActions: PulseItem {
        item(
            id: "slack:message:launch-date",
            source: .slack,
            kind: .decision,
            title: "Pick the launch date for the Payments beta",
            detail: "Priya needs a yes on Oct 28 or Nov 4 before she books the customer webinar.",
            url: "https://slack.example.com/archives/C123/p456",
            due: after(hour(9)),
            priority: .high,
            people: ["Priya Raman", "Marco Alves"],
            firstSeenAt: ago(hour(5)),
            lastSeenAt: ago(hour(5)),
            quickActions: [
                QuickAction(label: "Yes to Oct 28", text: "Oct 28 works — go ahead and book it."),
                QuickAction(label: "Yes to Nov 4", text: "Nov 4 works for me."),
                QuickAction(label: "Open thread", url: "https://slack.example.com/archives/C123/p456"),
            ]
        )
    }

    public static var longTitleForDynamicType: PulseItem {
        item(
            id: "calendar:event:long",
            kind: .review,
            title: "Read the full accessibility audit of the onboarding flow before the design review on Monday afternoon",
            detail: "Twenty two findings, three of them blocking. Two need a decision from you before the review.",
            due: after(day(2)),
            priority: .normal,
            people: ["Dana Whitfield", "Sam Okoro"],
            firstSeenAt: ago(hour(8)),
            lastSeenAt: ago(hour(8))
        )
    }

    public static var waitingItem: PulseItem {
        item(
            id: "gmail:message:legal-signoff",
            source: .gmail,
            kind: .followup,
            title: "Legal sign-off on the data addendum",
            detail: "Sent to counsel on Tuesday; waiting on their redlines.",
            priority: .normal,
            people: ["Marco Alves"],
            status: .waiting,
            firstSeenAt: ago(day(3)),
            lastSeenAt: ago(day(1))
        )
    }

    // MARK: Sets

    public enum FixtureSet {
        /// A realistic twelve-item board across all four horizons.
        public static func board(count: Int = 12) -> [PulseItem] {
            let core: [PulseItem] = [
                Fixtures.highPriorityRSVP,
                Fixtures.imminentMeeting,
                Fixtures.overdueReminder,
                Fixtures.conflict,
                Fixtures.withThreeQuickActions,
                Fixtures.waitingItem,
                Fixtures.longTitleForDynamicType,
                Fixtures.snoozedUntilTomorrow,
                Fixtures.item(
                    id: "reminders:reminder:book-travel",
                    source: .other,
                    kind: .deadline,
                    title: "Book travel for the offsite",
                    due: Fixtures.after(Fixtures.day(2)),
                    priority: .normal,
                    firstSeenAt: Fixtures.ago(Fixtures.hour(10)),
                    lastSeenAt: Fixtures.ago(Fixtures.hour(10))
                ),
                Fixtures.item(
                    id: "gmail:message:partnership",
                    source: .gmail,
                    kind: .reply,
                    title: "Reply to the partnership intro",
                    detail: "Warm intro from Dana; a two-line yes is enough.",
                    due: Fixtures.after(Fixtures.day(5)),
                    people: ["Dana Whitfield"],
                    firstSeenAt: Fixtures.ago(Fixtures.day(1)),
                    lastSeenAt: Fixtures.ago(Fixtures.day(1))
                ),
                Fixtures.fyiLink,
                Fixtures.item(
                    id: "docs:page:retro-notes",
                    source: .docs,
                    kind: .fyi,
                    title: "Retro notes from last sprint",
                    priority: .low,
                    firstSeenAt: Fixtures.ago(Fixtures.hour(6)),
                    lastSeenAt: Fixtures.ago(Fixtures.hour(6))
                ),
            ]
            return Array(core.prefix(count))
        }

        /// A board grouped the way `ItemStore.board(at:)` would group it.
        public static func grouped(count: Int = 12, now: Date = Fixtures.fixtureNow) -> [Horizon: [PulseItem]] {
            var buckets: [Horizon: [PulseItem]] = [:]
            for item in board(count: count) {
                guard let horizon = HorizonDerivation.horizon(of: item, at: now, calendar: Fixtures.calendar()) else { continue }
                buckets[horizon, default: []].append(item)
            }
            for key in buckets.keys {
                buckets[key] = PulseItemSort.sorted(buckets[key] ?? [])
            }
            return buckets
        }

        public static var closed: [PulseItem] {
            [Fixtures.doneWithReason, Fixtures.dismissed(), Fixtures.resolved()]
        }
    }
}

/// The seeded store the demo build launches with. Lives here because `Fixtures`
/// is debug-only.
enum FixtureStore {
    /// The board plus the recently closed items, so the closed-review screen and
    /// the Reopen flow are reachable in a demo build.
    static func make() -> ItemStore {
        ItemStore(
            items: Fixtures.FixtureSet.board() + Fixtures.FixtureSet.closed,
            lastViewedAt: Fixtures.ago(7_200)
        )
    }
}
#endif
