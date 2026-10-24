import Foundation
import ThirdHandCore
import Testing
@testable import ThirdHand

/// The projection the widgets and intents render (#29-#32).
///
/// All of it is pure: `WidgetSnapshot` in, strings and counts out. That is what makes
/// these assertable in `ThirdHandTests` at all -- the widget extension has no test host,
/// so anything that lived in the extension would be untested by construction.
@Suite("Widget presentation")
struct WidgetPresentationTests {
    private let base = Date(timeIntervalSince1970: 1_793_059_200) // 2026-10-27 00:00 UTC
    /// UTC, en_US, so the formatted hints are the same on any machine and simulator.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func item(
        _ id: String,
        title: String = "An item",
        priority: Priority = .normal,
        due: Date? = nil,
        horizon: Horizon = .now,
        kind: Kind = .followup
    ) -> WidgetItem {
        WidgetItem(
            sampleID: id,
            title: title,
            kind: kind.rawValue,
            priority: priority.rawValue,
            due: due,
            horizon: horizon.rawValue
        )
    }

    private func snapshot(_ items: [WidgetItem], nowCount: Int? = nil) -> WidgetSnapshot {
        WidgetSnapshot(nowCount: nowCount ?? items.count, nowItems: items, generatedAt: base, hasBoard: true)
    }

    // MARK: Timeline entry projection

    @Test("Only Now items reach the widget")
    func filtersToNowHorizon() {
        let board = WidgetBoard(
            generatedAt: base,
            nowCount: 1,
            items: [
                item("a", horizon: .now),
                item("b", horizon: .next),
                item("c", horizon: .later),
                item("d", horizon: .niceToKnow),
            ]
        )
        let projected = WidgetSnapshot(board: board)
        #expect(projected.nowItems.map(\.id) == ["a"])
        #expect(projected.nowCount == 1)
        #expect(projected.hasBoard)
    }

    @Test("Order is priority, then due, then stored position")
    func ordersByPriorityThenDue() {
        let late = item("late", priority: .normal, due: base.addingTimeInterval(7_200))
        let soon = item("soon", priority: .normal, due: base.addingTimeInterval(600))
        let undated = item("undated", priority: .normal, due: nil)
        let urgent = item("urgent", priority: .high, due: base.addingTimeInterval(9_000))

        let ordered = WidgetOrdering.sorted([late, soon, undated, urgent])
        #expect(ordered.map(\.id) == ["urgent", "soon", "late", "undated"])
    }

    @Test("A missing board is the empty, unconfigured state")
    func missingBoard() {
        let projected = WidgetSnapshot(board: nil)
        #expect(projected.nowCount == 0)
        #expect(projected.nowItems.isEmpty)
        #expect(projected.generatedAt == nil)
        #expect(!projected.hasBoard)
        #expect(projected.needsSetup)
    }

    @Test("An empty but present board is not the setup state")
    func emptyBoardIsNotSetup() {
        let projected = WidgetSnapshot(board: WidgetBoard(generatedAt: base, nowCount: 0, items: []))
        #expect(projected.hasBoard)
        #expect(!projected.needsSetup)
        #expect(projected.isEmpty)
    }

    @Test("topItems and hiddenCount agree")
    func topItemsAndHidden() {
        let projected = snapshot((1...5).map { item("i\($0)") })
        #expect(projected.topItems(limit: 3).map(\.id) == ["i1", "i2", "i3"])
        #expect(projected.hiddenCount(limit: 3) == 2)
        #expect(projected.hiddenCount(limit: 9) == 0)
        // A negative limit is a programming error, not a crash on the Lock Screen.
        #expect(projected.topItems(limit: -1).isEmpty)
        #expect(projected.hiddenCount(limit: -1) == 5)
    }

    @Test("Urgency reflects the loudest item and the count")
    func urgency() {
        #expect(snapshot([]).urgency == .clear)
        #expect(snapshot([item("a")]).urgency == .normal)
        #expect(snapshot([item("a"), item("b"), item("c")]).urgency == .elevated)
        #expect(snapshot([item("a", priority: .high)]).urgency == .high)
    }

    @Test("Age text is relative and never negative")
    func ageText() {
        let projected = snapshot([])
        #expect(projected.ageText(now: base) == "now")
        #expect(projected.ageText(now: base.addingTimeInterval(120)) == "2m")
        #expect(projected.ageText(now: base.addingTimeInterval(7_200)) == "2h")
        #expect(projected.ageText(now: base.addingTimeInterval(172_800)) == "2d")
        // A clock that went backwards must not render "-1m".
        #expect(projected.ageText(now: base.addingTimeInterval(-60)) == "now")
        #expect(WidgetSnapshot().ageText(now: base) == "")
    }

    // MARK: Circular

    @Test("The circular gauge caps its numeral at 10+")
    func circularValue() {
        #expect(WidgetCopy.circularValue(0) == "0")
        #expect(WidgetCopy.circularValue(9) == "9")
        #expect(WidgetCopy.circularValue(10) == "9+")
        #expect(WidgetCopy.circularValue(120) == "9+")
    }

    @Test("The circular gauge fills to the cap, not past it")
    func circularFraction() {
        #expect(WidgetCopy.circularFraction(0) == 0)
        #expect(WidgetCopy.circularFraction(9) == 1)
        #expect(WidgetCopy.circularFraction(18) == 1)
        #expect(abs(WidgetCopy.circularFraction(3) - 1.0 / 3.0) < 0.0001)
    }

    // MARK: Inline

    @Test("Inline copy reads count then title")
    func inlineLine() {
        let projected = snapshot([item("a", title: "Design review")])
        #expect(WidgetCopy.inlineLine(projected) == "1 need you \u{00B7} Design review")
    }

    @Test("Inline copy is empty-state text with no items")
    func inlineEmpty() {
        #expect(WidgetCopy.inlineLine(snapshot([])) == "Nothing needs you")
    }

    @Test("Inline copy truncates at a word boundary within the budget")
    func inlineTruncatesAtWord() {
        let long = item("a", title: "Review the quarterly platform architecture proposal")
        let line = WidgetCopy.inlineLine(snapshot([long]))
        // The title half must fit the documented budget plus the ellipsis.
        let title = line.replacingOccurrences(of: "1 need you \u{00B7} ", with: "")
        #expect(title.count <= WidgetCopy.inlineTitleLimit + 1)
        #expect(title.hasSuffix("\u{2026}"))
        #expect(!title.contains("archite\u{2026}"))
        #expect(title.contains("quarterly"))
    }

    @Test("Truncation keeps short text untouched and hard-cuts one long word")
    func truncateEdgeCases() {
        #expect(WidgetCopy.truncate("Short", limit: 24) == "Short")
        #expect(WidgetCopy.truncate("  padded  ", limit: 24) == "padded")
        #expect(WidgetCopy.truncate("Supercalifragilisticexpialidocious", limit: 10) == "Supercalif\u{2026}")
    }

    // MARK: Rectangular

    @Test("Rectangular copy names the top item and its due hint")
    func rectangular() {
        let projected = snapshot([
            item("a", title: "Design review", priority: .high, due: base.addingTimeInterval(2_400)),
            item("b", title: "Second"),
            item("c", title: "Third"),
        ])
        #expect(WidgetCopy.rectangularTitle(projected) == "Design review")
        let detail = WidgetCopy.rectangularDetail(projected, now: base, calendar: calendar)
        #expect(detail.contains("3 need you"))
        #expect(detail.contains("in 40m"))
        #expect(detail.contains("+2 more"))
    }

    @Test("Rectangular copy never invents a due time")
    func rectangularNoDue() {
        let projected = snapshot([item("a", title: "Reply in #platform")])
        let detail = WidgetCopy.rectangularDetail(projected, now: base, calendar: calendar)
        #expect(detail == "1 needs you")
    }

    @Test("Rectangular empty state")
    func rectangularEmpty() {
        let projected = snapshot([])
        #expect(WidgetCopy.rectangularTitle(projected) == "Nothing needs you")
        #expect(WidgetCopy.rectangularDetail(projected, now: base, calendar: calendar).isEmpty)
    }

    // MARK: Due hint

    @Test("Due hints: overdue, relative, today, tomorrow, this week, later")
    func dueHints() {
        let now = base
        #expect(WidgetCopy.dueHint(base.addingTimeInterval(-60), now: now, calendar: calendar) == "overdue")
        #expect(WidgetCopy.dueHint(base.addingTimeInterval(600), now: now, calendar: calendar) == "in 10m")
        #expect(WidgetCopy.dueHint(base.addingTimeInterval(3_600), now: now, calendar: calendar) == "in 60m")
        #expect(WidgetCopy.dueHint(base.addingTimeInterval(3_660), now: now, calendar: calendar).hasPrefix("Today "))
        #expect(WidgetCopy.dueHint(base.addingTimeInterval(86_400), now: now, calendar: calendar) == "Tomorrow")
        let fourDays = WidgetCopy.dueHint(base.addingTimeInterval(4 * 86_400), now: now, calendar: calendar)
        #expect(fourDays.hasPrefix("Tue ") || fourDays.hasPrefix("Wed ") || fourDays.hasPrefix("Thu ")
                || fourDays.hasPrefix("Fri ") || fourDays.hasPrefix("Sat ") || fourDays.hasPrefix("Sun ")
                || fourDays.hasPrefix("Mon "))
        #expect(WidgetCopy.dueHint(base.addingTimeInterval(20 * 86_400), now: now, calendar: calendar) == "Nov 16")
    }

    @Test("Counting copy agrees across surfaces")
    func countCopy() {
        #expect(WidgetCopy.needYou(0) == "Nothing needs you")
        #expect(WidgetCopy.needYou(1) == "1 needs you")
        #expect(WidgetCopy.needYou(3) == "3 need you")
        #expect(WidgetCopy.countAccessibilityLabel(0) == "Nothing needs you")
        #expect(WidgetCopy.countAccessibilityLabel(1) == "1 item needs you")
        #expect(WidgetCopy.countAccessibilityLabel(4) == "4 items need you")
    }

    @Test("Attendee names survive the projection and are optional")
    func peopleProjection() throws {
        let withPeople = WidgetItem(
            sampleID: "calendar:event:a",
            title: "Design review",
            kind: Kind.review.rawValue,
            priority: Priority.high.rawValue,
            due: base,
            horizon: Horizon.now.rawValue,
            people: ["Priya Raman", "Marco Silva"]
        )
        let data = try ThirdHandJSON.makeEncoder().encode(withPeople)
        let decoded = try ThirdHandJSON.makeDecoder().decode(WidgetItem.self, from: data)
        #expect(decoded.people == ["Priya Raman", "Marco Silva"])

        // A projection written before `people` existed must still decode.
        let legacy = Data(#"{"id":"x","title":"t","kind":"reply","priority":"normal","horizon":"now"}"#.utf8)
        #expect(try ThirdHandJSON.makeDecoder().decode(WidgetItem.self, from: legacy).people == nil)
    }

    // MARK: Live Activity start decision

    @Test("An item inside the window is imminent")
    func imminentInsideWindow() {
        let projected = snapshot([
            item("later", due: base.addingTimeInterval(2 * 3_600)),
            item("soon", due: base.addingTimeInterval(2_400)),
        ])
        #expect(ImminentItemRule.imminentItem(projected, now: base)?.id == "soon")
    }

    @Test("The 60-minute boundary is inclusive")
    func imminentBoundary() {
        let exactly = snapshot([item("a", due: base.addingTimeInterval(3_600))])
        #expect(ImminentItemRule.imminentItem(exactly, now: base)?.id == "a")

        let past = snapshot([item("a", due: base.addingTimeInterval(3_601))])
        #expect(ImminentItemRule.imminentItem(past, now: base) == nil)
    }

    @Test("A meeting that already started is not imminent")
    func imminentExcludesStarted() {
        let projected = snapshot([item("a", due: base.addingTimeInterval(-60))])
        #expect(ImminentItemRule.imminentItem(projected, now: base) == nil)
    }

    @Test("An item with no due date is never imminent")
    func imminentNeedsDue() {
        #expect(ImminentItemRule.imminentItem(snapshot([item("a")]), now: base) == nil)
    }

    @Test("The nearest imminent item wins regardless of board order")
    func imminentNearest() {
        let projected = snapshot([
            item("further", priority: .high, due: base.addingTimeInterval(3_000)),
            item("nearer", due: base.addingTimeInterval(600)),
        ])
        #expect(ImminentItemRule.imminentItem(projected, now: base)?.id == "nearer")
    }

    @Test("Starting is skipped when the item already describes the running activity")
    func shouldStartDedupes() {
        let projected = snapshot([item("a", due: base.addingTimeInterval(600))])
        #expect(ImminentItemRule.shouldStart(snapshot: projected, now: base, runningItemID: nil)?.id == "a")
        #expect(ImminentItemRule.shouldStart(snapshot: projected, now: base, runningItemID: "a") == nil)
        // A different running item is replaced, not duplicated.
        #expect(ImminentItemRule.shouldStart(snapshot: projected, now: base, runningItemID: "b")?.id == "a")
    }

    @Test("An activity ends when its item leaves the board")
    func shouldEnd() {
        let projected = snapshot([item("a")])
        #expect(!ImminentItemRule.shouldEnd(runningItemID: "a", snapshot: projected))
        #expect(ImminentItemRule.shouldEnd(runningItemID: "gone", snapshot: projected))
    }

    @Test("Countdown copy rounds up and never says zero")
    func countdown() {
        #expect(ImminentItemRule.countdownText(base.addingTimeInterval(600), now: base) == "in 10 min")
        #expect(ImminentItemRule.countdownText(base.addingTimeInterval(30), now: base) == "in 1 min")
        #expect(ImminentItemRule.countdownText(base, now: base) == "starting now")
    }

    // MARK: Intents

    @Test("Intent summary: empty board")
    func intentEmpty() {
        #expect(IntentSummary.whatNeedsMe(snapshot([], nowCount: 0), now: base, calendar: calendar) == "Nothing needs you.")
    }

    @Test("Intent summary: one item")
    func intentOne() {
        let projected = snapshot([item("a", title: "Design review", due: base.addingTimeInterval(2_400))])
        let spoken = IntentSummary.whatNeedsMe(projected, now: base, calendar: calendar)
        #expect(spoken == "1 thing needs you: Design review, in 40m.")
    }

    @Test("Intent summary: many items names two and counts the rest")
    func intentMany() {
        let projected = snapshot([
            item("a", title: "Design review", priority: .high, due: base.addingTimeInterval(2_400)),
            item("b", title: "RSVP to Priya", priority: .high, due: base.addingTimeInterval(3_600)),
            item("c", title: "Send the invoice"),
        ])
        let spoken = IntentSummary.whatNeedsMe(projected, now: base, calendar: calendar)
        #expect(spoken.hasPrefix("3 things need you: "))
        #expect(spoken.contains("Design review, in 40m"))
        #expect(spoken.contains("RSVP to Priya, in 60m"))
        #expect(spoken.hasSuffix(" and 1 more."))
        #expect(!spoken.contains("Send the invoice"))
    }

    @Test("Intent summary: an item with no due date is named without a time")
    func intentNoDue() {
        let projected = snapshot([item("a", title: "Reply in #platform")])
        #expect(IntentSummary.whatNeedsMe(projected, now: base, calendar: calendar)
                == "1 thing needs you: Reply in #platform.")
    }

    @Test("Snooze dialogs name the item and the time")
    func snoozeDialogs() {
        let until = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base.addingTimeInterval(86_400))!
        #expect(IntentSummary.snoozed(title: "Design review", until: until, calendar: calendar)
                == "Snoozed Design review until 9:00\u{202F}AM.")
        #expect(IntentSummary.nothingToSnooze == "Nothing needs you, so there was nothing to snooze.")
    }
}
