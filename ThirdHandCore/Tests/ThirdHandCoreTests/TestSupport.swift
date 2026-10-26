import Foundation
import Testing
@testable import ThirdHandCore

// Force-unwrapping is the fixture style in this file on purpose: these are fixed
// literals (a fixed-offset calendar, a hard-coded instant), and a bad one is a broken
// test that should stop the run at the line that built it, not a condition the code
// under test is asked to handle.

/// A fixed UTC calendar so day-boundary tests do not depend on the machine's
/// timezone or locale.
enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// 2026-10-23T18:04:11.000Z -- the instant from the contract's example snapshot.
    static let now = Date(timeIntervalSince1970: 1_792_778_651)

    static func date(_ iso: String) -> Date {
        guard let date = ThirdHandJSON.dates.date(from: iso) else {
            fatalError("bad fixture date \(iso)")
        }
        return date
    }

    static func detected(
        _ id: String,
        title: String? = "Something",
        detail: String? = nil,
        url: String? = nil,
        due: Date? = nil,
        kind: Kind? = nil,
        priority: Priority? = nil,
        status: Status? = nil,
        people: [String]? = nil,
        quickActions: [QuickAction]? = nil,
        reopen: Bool = false,
        reason: String? = nil
    ) -> DetectedItem {
        DetectedItem(
            id: id,
            kind: kind,
            title: title,
            detail: detail,
            url: url,
            due: due,
            priority: priority,
            people: people,
            status: status,
            quickActions: quickActions,
            reopen: reopen,
            reason: reason
        )
    }

    /// A fully-populated item: every field non-default, so a round trip that
    /// drops a field fails loudly.
    static func fullItem(id: String = "calendar:event:ABC-123") -> ThirdHandItem {
        ThirdHandItem(
            id: id,
            source: .calendar,
            kind: .conflict,
            title: "Standup overlaps Design review",
            detail: "Two accepted events overlap by 12 minutes.\nPick one.",
            url: "https://calendar.example.com/event/ABC-123",
            due: date("2026-10-23T18:04:11.123Z"),
            priority: .high,
            people: ["Ada Lovelace", "Grace Hopper"],
            status: .waiting,
            snoozedUntil: date("2026-10-24T09:00:00.001Z"),
            resolution: "Moved Design review",
            firstSeenAt: date("2026-10-20T07:15:00.250Z"),
            lastSeenAt: date("2026-10-23T17:59:59.999Z"),
            updatedAt: date("2026-10-23T18:00:00.000Z"),
            resolvedAt: date("2026-10-22T11:11:11.111Z"),
            lastChangedBy: "capture",
            history: [
                HistoryEntry(
                    at: date("2026-10-20T07:15:00.250Z"),
                    by: "morning",
                    change: "created"
                ),
                HistoryEntry(
                    at: date("2026-10-22T11:11:11.111Z"),
                    by: "user",
                    change: "snoozed",
                    reason: "after standup",
                    until: date("2026-10-23T09:00:00.000Z")
                )
            ],
            quickActions: [
                QuickAction(label: "Decline", text: "I cannot make this one."),
                QuickAction(label: "Open event", url: "https://calendar.example.com/e/1"),
                QuickAction(label: "Both", text: "note", url: "https://example.com/x")
            ],
            agentSkills: ["calendar-triage", "conflict-resolve"],
            action: ThirdHandItemAction(
                threadId: "thr_abc123",
                status: .ready,
                startedAt: date("2026-10-23T18:01:00.000Z"),
                finishedAt: date("2026-10-23T18:03:30.500Z"),
                summary: "Ready: drafted a decline note",
                seenAt: date("2026-10-23T18:04:00.000Z")
            )
        )
    }
}
