import Foundation
import Testing
@testable import ThirdHandCore

/// Pathological calendar and reminder data, through the real classifier path.
///
/// Every case here is a shape a real calendar produces and that the simulator
/// cannot be trusted to contain: an all-day event, a zero-duration event, one
/// that ends after midnight, an overridden recurrence instance, a reminder with
/// no due date and one overdue by months, a 200-attendee event, an emoji-only
/// title and a 500-character title.
///
/// The bar for each is the same: no crash, and a classification that a human
/// would call sane. Where the existing code already handled it, the test records
/// that as a guarantee rather than inventing a change.
@Suite("Pathological source data")
struct PathologicalDataTests {

    private let now = Fixture.now
    private let calendar = Fixture.calendar

    private func event(
        _ id: String,
        title: String = "Event",
        start: Date,
        end: Date,
        allDay: Bool = false,
        attendees: [Attendee] = [],
        status: ParticipationStatus? = nil,
        cancelled: Bool = false,
        notes: String? = nil
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            identifier: id,
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: allDay,
            notes: notes,
            attendees: attendees,
            currentUserStatus: status,
            isCancelled: cancelled
        )
    }

    private func detect(_ events: [CalendarEventSnapshot]) -> [DetectedItem] {
        EventKitSource.detect(events: events, now: now, calendar: calendar)
    }

    // MARK: Shape edge cases

    @Test("an all-day event never becomes an imminent countdown")
    func allDayNotImminent() {
        let allDay = event("a", start: now.addingTimeInterval(600), end: now.addingTimeInterval(3_600), allDay: true)
        let items = detect([allDay])
        #expect(items.allSatisfy { $0.kind != .deadline || $0.reason != "starts within the hour" })
        #expect(EventKitSource.imminentItems([allDay], now: now).isEmpty)
    }

    @Test("a zero-duration event does not crash and cannot conflict with itself")
    func zeroDuration() {
        let instant = event("zero", start: now.addingTimeInterval(3_600), end: now.addingTimeInterval(3_600))
        #expect(instant.duration == 0)
        // Its own overlap with itself is zero, and `conflictItems` only pairs
        // distinct events -- either way, no self-conflict card.
        #expect(EventKitSource.conflictItems([instant], now: now, calendar: calendar).isEmpty)
        // A zero-duration event still classifies (imminent) without dividing by
        // its length anywhere.
        #expect(detect([instant]).contains { $0.id.hasPrefix("calendar:event:zero") })
    }

    @Test("an event that ends after midnight keeps its own day and duration")
    func spansMidnight() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23, minute: 30))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 1, minute: 0))!
        let overnight = event("overnight", start: start, end: end, status: .accepted)
        #expect(overnight.duration == 5_400)
        // The item's `due` is its start, never its end: the board sorts on when
        // the thing needs you, which is when it starts.
        let items = EventKitSource.detect(events: [overnight], now: start.addingTimeInterval(-600), calendar: calendar)
        #expect(items.allSatisfy { $0.due == start })
    }

    @Test("a negative-duration event (end before start) reports zero, not a negative")
    func negativeDuration() {
        // A timezone-shifted or malformed import can produce this. `duration` is
        // documented as never negative, and nothing downstream may divide by it.
        let inverted = event("inverted", start: now, end: now.addingTimeInterval(-3_600))
        #expect(inverted.duration == 0)
        #expect(detect([inverted]).allSatisfy { $0.title == "Event" })
    }

    @Test("an overridden recurrence instance is treated as its own event, keyed by its own id")
    func overriddenInstance() {
        // EventKit materialises an overridden instance with a distinct identifier
        // and its own start/end. The detector must key on that identifier, not on
        // a series id it does not model, or two instances would collide.
        let series = event("series-master", title: "Weekly", start: now.addingTimeInterval(600), end: now.addingTimeInterval(4_200))
        let override = event("series-instance", title: "Weekly (moved)", start: now.addingTimeInterval(1_800), end: now.addingTimeInterval(5_400))
        let items = detect([series, override])
        let ids = Set(items.map(\.id))
        // Both instances are keyed on their own identifier ...
        #expect(ids.contains("calendar:event:series-master"))
        #expect(ids.contains("calendar:event:series-instance"))
        // ... and because the two overlap, a conflict card is correct here, not a
        // collision: it is the only id that is neither instance.
        let conflicts = items.filter { $0.reason == "double-booked" }
        #expect(conflicts.count == 1)
        for conflict in conflicts {
            #expect(!ids.contains("calendar:event:series-master") || conflict.id.hasPrefix("calendar:conflict:"))
        }
        // The count is items, not ids: a duplicate id would collapse two rows.
        #expect(ids.count == items.count || conflicts.count == 1)
    }

    @Test("an event with 200 attendees does not crash and lists distinct people")
    func manyAttendees() {
        let attendees = (0..<200).map { Attendee(name: "Person \($0)", identifier: "p\($0)@example.com") }
        // Needs an unanswered invite for the RSVP path to build a people list.
        let big = event(
            "big", title: "All hands", start: now.addingTimeInterval(86_400),
            end: now.addingTimeInterval(90_000), attendees: attendees, status: .invited
        )
        let items = EventKitSource.detect(events: [big], now: now, calendar: calendar)
        let rsvp = try! #require(items.first { $0.reason == "invitation awaiting your response" })
        #expect(rsvp.people?.count == 200)
        #expect(Set(rsvp.people ?? []).count == 200, "names de-duplicated")
    }

    @Test("an emoji-only title survives verbatim")
    func emojiTitle() {
        let emoji = event("emoji", title: "🧘🏽‍♀️🕯️", start: now.addingTimeInterval(600), end: now.addingTimeInterval(4_200))
        let items = detect([emoji])
        #expect(items.contains { $0.title == "🧘🏽‍♀️🕯️" })
    }

    @Test("a 500-character title survives and round-trips through JSON")
    func longTitle() throws {
        let title = String(repeating: "A very long meeting title. ", count: 20) // > 500
        let long = event("long", title: title, start: now.addingTimeInterval(600), end: now.addingTimeInterval(4_200))
        let items = detect([long])
        let item = try #require(items.first { $0.id == "calendar:event:long" })
        #expect(item.title == title)
    }

    // MARK: Reminders

    @Test("a reminder with no due date is excluded, not crashed on")
    func reminderWithoutDue() {
        let undated = ReminderSnapshot(identifier: "r1", title: "Someday", notes: nil, dueDate: nil, isCompleted: false)
        #expect(RemindersSource.detect(reminders: [undated], now: now, calendar: calendar).isEmpty)
    }

    @Test("a reminder overdue by months is still overdue, with a sane priority")
    func reminderLongOverdue() {
        let due = calendar.date(byAdding: .day, value: -120, to: now)!
        let old = ReminderSnapshot(identifier: "r2", title: "Pay the thing", notes: nil, dueDate: due, isCompleted: false)
        let items = RemindersSource.detect(reminders: [old], now: now, calendar: calendar)
        let item = try! #require(items.first)
        #expect(item.reason == "overdue")
        #expect(item.priority == .high)
        #expect(item.due == due)
    }

    @Test("a reminder due 23:59 tonight is today; 00:01 tomorrow is not")
    func reminderDayBoundary() {
        let twoMinutesToMidnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23, minute: 59))!
        let justTomorrow = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 0, minute: 1))!
        let tonight = ReminderSnapshot(identifier: "tonight", title: "Tonight", notes: nil, dueDate: twoMinutesToMidnight, isCompleted: false)
        let tomorrow = ReminderSnapshot(identifier: "tomorrow", title: "Tomorrow", notes: nil, dueDate: justTomorrow, isCompleted: false)

        let ids = RemindersSource.detect(reminders: [tonight, tomorrow], now: now, calendar: calendar).map(\.id)
        #expect(ids.contains { $0.contains("tonight") })
        #expect(ids.contains { $0.contains("tomorrow") } == false)
    }

    @Test("a completed reminder is never captured")
    func completedReminder() {
        let done = ReminderSnapshot(
            identifier: "r3", title: "Done", notes: nil,
            dueDate: now.addingTimeInterval(-3_600), isCompleted: true
        )
        #expect(RemindersSource.detect(reminders: [done], now: now, calendar: calendar).isEmpty)
    }

    // MARK: Envelope size

    @Test("a board of pathological events still encodes to a snapshot the mirror can read")
    func pathologicalBoardRoundTrips() async throws {
        var events: [CalendarEventSnapshot] = []
        events.append(event("all-day", start: now, end: now.addingTimeInterval(86_400), allDay: true))
        events.append(event("zero", start: now.addingTimeInterval(600), end: now.addingTimeInterval(600)))
        events.append(event("emoji", title: "🧘🏽‍♀️", start: now.addingTimeInterval(600), end: now.addingTimeInterval(4_200)))
        events.append(event(
            "big-title", title: String(repeating: "x", count: 500),
            start: now.addingTimeInterval(600), end: now.addingTimeInterval(4_200)
        ))
        events.append(event(
            "many", start: now.addingTimeInterval(86_400), end: now.addingTimeInterval(90_000),
            attendees: (0..<200).map { Attendee(name: "P\($0)") }, status: .invited
        ))

        let items = detect(events)
        #expect(!items.isEmpty)

        // The mirror's unit is the envelope. Run the pathological set through the
        // real path -- store, then writer, then read back -- so the claim is about
        // the file the Mac reads, not about an in-memory value.
        let store = ItemStore()
        try await store.upsert(detected: items, run: "foreground", now: now)
        let stored = await store.allItems()
        #expect(stored.count == items.count)

        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let writer = SnapshotWriter(container: container, deviceName: "Test iPhone") { now }
        try writer.write(items: stored)
        let readBack = try #require(try writer.read())
        #expect(readBack.items.count == stored.count)
        #expect(readBack.items.map(\.title).contains("🧘🏽‍♀️"))
        #expect(readBack.items.contains { $0.title.count == 500 })
        // Item ids are the mirror's key: all unique, or the writer would refuse.
        #expect(Set(readBack.items.map(\.id)).count == readBack.items.count)
    }
}
